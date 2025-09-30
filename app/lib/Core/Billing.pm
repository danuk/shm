package Core::Billing;

use v5.14;

use base qw(
    Core::Pay
    Core::User
);

use base qw(Exporter);

our @EXPORT = qw(
    create_service
    process_service_recursive
    money_back
    calc_withdraw
    switch_to_next_service
);

use Core::Const;
use Core::Utils qw(now string_to_utime utime_to_string start_of_month end_of_month parse_date days_in_months);
use Time::Local 'timelocal_nocheck';

use base qw( Core::System::Service );
use Core::System::ServiceManager qw( get_service logger );

use Core::Billing::Honest;
use Core::Billing::Simpler;

sub awaiting_payment {
    my $self = shift;

    return 1 if (   $self->get_status eq STATUS_BLOCK ||
                    $self->get_status eq STATUS_WAIT_FOR_PAY );
    return 0;
}

sub create_service {
    my %args = (
        service_id => undef,
        @_,
    );

    my $us = create_service_recursive( %args );

    return process_service_recursive( $us, EVENT_CREATE );
}

sub create_service_recursive {
    my %args = (
        service_id => undef,
        @_,
    );

    unless ( $args{ service_id } ) {
        logger->fatal( "Not exists service_id in args" );
    }

    my $service = get_service('service', _id => $args{service_id} );
    unless ( $service ) {
        logger->error( "Service not exists: $args{service_id}" );
        return undef;
    }

    if ( $service->get_period ) {
        $args{months} ||= $service->get_period;
    }

    $args{next} = $service->get_next;

    my $us = get_service('us')->add( %args );

    if ( $service->get_pay_always || !$args{parent} ) {
        my %srv = $service->get;
        my $wd_id = add_withdraw(
            $us,
            calc_withdraw( $us->billing, %srv, %args ),
        );
        unless ( $wd_id ) {
            logger->error( "Failed to add withdraw for user service: " . $us->id );
            return undef;
        }
        $us->set( withdraw_id => $wd_id );
    }

    my $ss = $service->subservices;
    for ( @{ $ss } ) {
        create_service_recursive( %{ $_ }, parent => $us->id );
    }

    return $us;
}

sub process_service_recursive {
    my $service = shift;
    my $event = shift || EVENT_PROLONGATE;

    return undef unless ref $service;

    if ( $event = process_service( $service, $event ) ) {
        logger->info('Process service: '. $service->id . ", Result: [$event]" );
        for my $child ( @{$service->children} ) {
            process_service_recursive(
                $service->id( $child->id ),
                $event,
            );
        }
        $service->event( $event );
    }
    return $service;
}

# Просмотр/обработка услуг:
# Обработка новой услуги
# Выход из ф-ии если услуга не истекла
# Уже заблокированная услуга проверяется на предмет поступления средств и делается попытка продлить услугу
# Для истекшей, но активной услуги, создается акт
# Попытка продить услугу
# ф-я возвращает event (на вход пришел prolongate, а на выходе может быть block, если не хватило денег)
sub process_service {
    my $self = shift;
    my $event = shift;

    logger->info('Process service: '. $self->id . ", Event: [$event]" );

    if ( $self->get_status eq STATUS_PROGRESS ) {
        logger->info('Service in progress. Skipping...');
        return undef;
    }

    if ( $self->get_status eq STATUS_REMOVED ) {
        logger->warning('Service is removed. Skipping...');
        return undef;
    }

    unless ( $self->get_withdraw_id ) {
        # Бесплатная услуга
        return $event;
    }

    if ( $event eq EVENT_BLOCK_FORCE ) {
        return block( $self );
    } elsif ( $event eq EVENT_ACTIVATE_FORCE ) {
        return activate( $self );
    } elsif ( $event eq EVENT_REMOVE ) {
        return remove( $self );
    }

    unless ( $self->get_expire ) {
        # Новая услуга
        logger->info('New service');
        return create( $self );
    }

    unless ( $self->has_expired ) {
        # Услуга не истекла
        # Ничего не делаем с этой услугой
        logger->info('Service is not expired. Skipping...');
        return undef;
    }

    return prolongate( $self );
}

sub add_withdraw {
    my $us = shift;
    my %wd = @_;

    delete @wd{ qw/ withdraw_id create_date end_date withdraw_date user_service_id / };
    return $us->srv('wd', usi => $us->id )->add( %wd );
}

# Создание следущего платежа на основе текущего
sub add_withdraw_next {
    my $self = shift;

    my $wd = $self->withdraw->get;

    my %wd = calc_withdraw(
        $self->billing,
        %{ $wd },
        months => $self->service->get_period,
        bonus => 0,
    );

    return add_withdraw( $self, %wd );
}

# Вычисляет итоговую стоимость услуги
# на вход принимает все аргументы списания
sub calc_withdraw {
    my $billing = shift;
    my %wd = (
        cost => undef,
        months => undef,
        discount => 0,
        qnt => 1,
        @_,
    );

    $wd{qnt} = 1 if $wd{qnt} < 1;

    my %service = get_service( 'service', _id => $wd{service_id} )->get;
    $wd{months} ||= $wd{period};
    %wd = ( %service, %wd );

    $wd{withdraw_date}||= now;
    $wd{end_date} = calc_end_date_by_months( $billing, $wd{withdraw_date}, $wd{months} );

    if ( $wd{months} == $wd{period} ) {
        $wd{total} = $wd{cost};
    } else {
        $wd{total} = calc_total_by_date_range( $billing, %wd )->{total};
    }

    $wd{discount}||= get_service_discount( %wd );
    $wd{discount} = 0 if $service{no_discount};

    $wd{total} = sprintf("%.2f", ( $wd{total} - $wd{total} * $wd{discount} / 100 ) * $wd{qnt} );

    $wd{total} -= $wd{bonus};

    return %wd;
}

sub is_pay {
    my $self = shift;

    return undef unless $self->get_withdraw_id;
    unless ( $self->withdraw ) {
        logger->warning(
            sprintf( "Withdraw not exists: %d", $self->get_withdraw_id ),
        );
        return undef;
    }

    my $wd = $self->withdraw;
    # Already withdraw
    return 1 if $wd->get_withdraw_date;

    my $user = $self->user;
    my $balance = $user->get_balance + $user->get_credit;
    my $bonus = $user->get_bonus;
    my $total = $wd->get_total;

    my $root = $self->top_parent;
    if ( $root->service->get_is_composite ) {
        if ( $self->id == $root->id ) {
            # I'm a root
            $total = $self->wd_total_composite;
        } else {
            # I'm a child
            return 0 unless $root->is_paid;
        }
    }

    # Not enough money
    return 0 if (
                    $total > 0 &&
                    $balance + $bonus < $total &&
                    !$user->get_can_overdraft &&
                    !$self->get_pay_in_credit );

    # refresh total after composite services
    $total = $wd->get_total;

    if ( $bonus >= $total ) {
        $bonus = $total;
        $total = 0;
    } else {
        $total -= $bonus;
    }

    $user->set_bonus( bonus => -$bonus, comment => { withdraw_id => $wd->id } );
    $user->set_balance( balance => -$total );

    $wd->set(
        bonus => $bonus,
        total => $total,
        withdraw_date => now,
    );

    return 1;
}

sub set_service_expire {
    my $self = shift;

    my $wd = $self->withdraw->get;
    my $now = now;

    if ( $self->has_expired && $self->get_status ne STATUS_BLOCK ) {
        # Услуга истекла (не новая) и не заблокирована ранее
        # Будем продлять с момента истечения
        $now = $self->get_expire;
    }

    my $expire_date = calc_end_date_by_months( $self->billing, $now, $wd->{months} );

    #if ( $config->{child_expire_by_parent} {
    #if ( my $parent_expire_date = parent_has_expired( $self ) ) {
    #     if ( $expire_date gt $parent_expire_date ) {
    #        # дата истечения услуги не должна быть больше чем дата истечения родителя
    #        $expire_date = $parent_expire_date;
    #        # TODO: cacl and set real months
    #    }
    #}}

    $self->withdraw->set( end_date => $expire_date );

    return $self->set( expire => $expire_date );
}

sub create {
    my $self = shift;
    my %args = (
        children_free => 0,
        @_,
    );

    unless ( is_pay( $self ) ) {
        logger->debug('Not enough money');
        return EVENT_NOT_ENOUGH_MONEY;
    }

    set_service_expire( $self ) unless $args{children_free};

    return EVENT_CREATE;
}

sub prolongate {
    my $self = shift;

    logger->info('Trying to prolong the service: ' . $self->id );

    unless (    $self->get_status eq STATUS_ACTIVE ||
                $self->get_status eq STATUS_WAIT_FOR_PAY ||
                $self->get_status eq STATUS_BLOCK
    ) {
        logger->warning( sprintf "Can't prolongate service %d with status: %s . Skipped", $self->id, $self->get_status );
        return undef;
    }

    unless ( $self->has_expired ) {
        logger->info("Service has not expired. Skipped");
        return undef;
    }

    if ( $self->parent_has_expired ) {
        # Не продлеваем услугу если родитель истек
        logger->info('Parent has expired. Skipped');
        return block( $self );
    }

    if ( $self->withdraw->paid && $self->get_next == -1 ) {
        return remove( $self );
    } elsif ( $self->withdraw->paid && $self->get_next ) {
        unless (switch_to_next_service( $self)) {
            logger->error( "Failed to switch to next service for user service: " . $self->id );
            return undef;
        }
    } elsif ( $self->withdraw->paid ) {
        # Для существующей услуги используем текущее/следующее/новое списание
        my $wd = $self->withdraw;
        if ( $wd && $wd->get_withdraw_date ) {
            my $wd_id;
            if ( my %next = $self->withdraw->next ) {
                $wd_id = $next{withdraw_id};
            } else {
                $wd_id = add_withdraw_next( $self );
                unless ( $wd_id ) {
                    logger->error( "Failed to add withdraw for user service: " . $self->id );
                    return undef;
                }
            }
            $self->set( withdraw_id => $wd_id );
        }
    }

    unless ( is_pay( $self ) ) {
        logger->info('Not enough money');
        return block( $self );
    }

    set_service_expire( $self );

    return EVENT_ACTIVATE if $self->get_status eq STATUS_WAIT_FOR_PAY || $self->get_status eq STATUS_BLOCK;
    return EVENT_PROLONGATE if $self->get_status eq STATUS_ACTIVE;
    return undef;
}

sub switch_to_next_service {
        my $us = shift;

        my $new_service_id = $us->get_next;
        unless ( $new_service_id ) {
            logger->warning( "Next service not exists for user service: " . $us->id );
            return;
        }

        my $service = get_service('service', _id => $new_service_id );
        unless ( $service ) {
            logger->warning( "Service not exists: $new_service_id" );
            return;
        }

        my %wd = calc_withdraw( $us->billing, $service->get );
        delete @wd{ qw/ create_date end_date withdraw_date user_service_id / };

        my $wd_id;
        my $wd = $us->withdraw;
        if ( $wd->unpaid ) {
            $wd->set( %wd );
        } else {
            $wd_id = add_withdraw(
                $us,
                %wd,
            );
            unless ($wd_id) {
                logger->error( "Failed to add withdraw for user service: " . $us->id );
                return;
            }
        }

        $us->set(
            service_id => $service->id,
            next => $service->get_next,
            $wd_id ? ( withdraw_id => $wd_id ) : (),
        );
        $us->make_commands_by_event( EVENT_CHANGED_TARIFF );
        return 1;
}

sub block {
    my $self = shift;
    return 0 if $self->get_status ne STATUS_ACTIVE;

    return EVENT_BLOCK;
}

sub activate {
    my $self = shift;
    return 0 unless $self->get_status eq STATUS_BLOCK;

    return EVENT_ACTIVATE;
}

sub remove {
    my $self = shift;
    return 0 if $self->get_status eq STATUS_REMOVED;

    money_back( $self );

    return EVENT_REMOVE;
}

# Анализируем услугу и решаем какую скидку давать (доменам не давать)
sub get_service_discount {
    my %args = (
        months => undef,
        service_id => undef,
        @_,
    );

    my $service = $args{service_id} ? get_service( 'service', _id => $args{service_id} )->get : {};

    $args{period} ||= $service->{period} // undef;
    $args{months} ||= $service->{period} || 1;

    my $percent = get_service('user')->get_discount || 0;

    if ( $args{period} < 2 ) {
        # Вычисляем скидку за кол-во месяцев
        my $discount_info = get_service('discounts')->get_by_period( months => $args{months} );
        if ( $discount_info ) {
            $percent += $discount_info->{percent};
        }
    }

    $percent = 100 if $percent > 100;
    return $percent;
}

sub money_back {
    my $self = shift;
    my $date = shift || $self->get_expire;

    return undef unless $self->get_withdraw_id;

    my $service = get_service('service', _id => $self->get_service_id );
    return undef unless $service;
    return undef if $service->settings->{no_money_back};

    my $wd = $self->withdraw;
    return undef unless $wd;

    my %wd = $wd->get;
    return undef unless $wd{end_date};
    return undef if $wd{end_date} le $date;
    return undef if $wd{create_date} gt $date;

    my $calc = calc_total_by_date_range(
        $self->billing,
        %{ $service->get },
        %wd,
        end_date => $date,
    );

    my ($delta_money, $delta_bonus) = (0, 0);

    if ($calc->{total} > $wd{total}) {
        $delta_money = $wd{total};
        $wd{total} = 0;

        $delta_bonus = $calc->{total} > $wd{bonus} ? $wd{bonus} : $calc->{total};
        $wd{bonus} -= $delta_bonus;
        $wd{bonus} = 0 if $wd{bonus} < 0;
    } else {
        $delta_money = $wd{total} - $calc->{total};
        $wd{total} = $calc->{total};
    }

    $wd{months}   = $calc->{months};
    $wd{end_date} = $date;

    $wd->set(
        months   => $wd{months},
        end_date => $wd{end_date},
        total    => $wd{total},
        bonus    => $wd{bonus},
    );

    $self->user->set_balance(
        balance => $delta_money,
        bonus   => $delta_bonus,
    );

    $self->user->bonus->add( bonus => $delta_bonus, comment => { withdraw_id => $wd->id } ) if $delta_bonus;

    return $delta_money, $delta_bonus;
}

sub calc_end_date_by_months {
    my $billing = shift;

    if ( $billing eq 'Honest' ) {
        return Core::Billing::Honest::calc_end_date_by_months( @_ );
    } else {
        return Core::Billing::Simpler::calc_end_date_by_months( @_ );
    }
}

sub calc_total_by_date_range {
    my $billing = shift;

    if ( $billing eq 'Honest' ) {
        return Core::Billing::Honest::calc_total_by_date_range( @_ );
    } else {
        return Core::Billing::Simpler::calc_total_by_date_range( @_ );
    }
}

1;
