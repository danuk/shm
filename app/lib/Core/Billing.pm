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

    unless ( $args{ service_id } ) {
        logger->error( "Not exists `$_` in args" );
    }

    my $service = get_service('service', _id => $args{service_id} );
    unless ( $service ) {
        logger->error( "Service not exists: $args{service_id}" );
    }

    my $us = get_service('us')->add( %args );

    my $wd_id = add_withdraw(
        calc_withdraw( $us->billing, $service->get, %args ),
        user_service_id => $us->id,
    );
    $us->set( withdraw_id => $wd_id );

    my $ss = get_service('service', _id => $args{service_id} )->subservices;
    for ( @{ $ss } ) {
        get_service('us')->add( service_id => $_, parent => $us->id );
    }

    return process_service_recursive( $us, EVENT_CREATE );
}

sub process_service_recursive {
    my $service = shift;
    my $event = shift || EVENT_PROLONGATE;

    if ( $event = process_service( $service, $event ) ) {
        for my $child ( $service->children ) {
            process_service_recursive(
                get_service('us', _id => $child->{user_service_id} ),
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

    logger->debug('Process service: '. $self->id . " Event: [$event]" );

    if ( $self->get_status eq STATUS_PROGRESS ) {
        logger->debug('Service in progress. Skipping...');
        return undef;
    }

    unless ( $self->get_withdraw_id ) {
        # Бесплатная услуга
        return $event;
    }

    unless ( $self->get_auto_bill ) {
        logger->debug('AUTO_BILL is OFF for service. Skipping...');
        return undef;
    }

    if ( $event eq EVENT_BLOCK ) {
        return block( $self );
    } elsif ( $event eq EVENT_ACTIVATE ) {
        return activate( $self );
    } elsif ( $event eq EVENT_REMOVE ) {
        return remove( $self );
    }

    unless ( $self->get_expire ) {
        # Новая услуга
        logger->debug('New service');
        return create( $self );
    }

    unless ( $self->has_expired ) {
        # Услуга не истекла
        # Ничего не делаем с этой услугой
        return undef;
    }

    # Продляем услугу
    return prolongate( $self );
}

sub add_withdraw {
    my %wd = @_;

    delete @wd{ qw/ withdraw_id create_date end_date withdraw_date / };
    return get_service('withdraw')->add( %wd );
}

# Создание следущего платежа на основе текущего
sub add_withdraw_next {
    my $self = shift;

    my $wd = $self->withdraw->get;

    my %wd = calc_withdraw(
        $self->billing,
        %{ $wd },
        #months => int $wd->{months},
        bonus => 0,
    );

    return add_withdraw( %wd );
}

# Вычисляет итоговую стоимость услуги
# на вход принимает все аргументы списания
sub calc_withdraw {
    my $billing = shift;
    my %wd = (
        cost => undef,
        months => 1,
        discount => 0,
        qnt => 1,
        @_,
    );

    my %service = get_service( 'service', _id => $wd{service_id} )->get;
    %wd = ( %service, %wd );

    $wd{withdraw_date}||= now;
    $wd{end_date} = calc_end_date_by_months( $billing, $wd{withdraw_date}, $wd{months} );

    if ( $wd{months} == $wd{period_cost} ) {
        $wd{total} = $wd{cost};
    } else {
        $wd{total} = calc_total_by_date_range( $billing, %wd )->{total};
    }

    $wd{discount}||= get_service_discount( %wd );
    $wd{discount} = 0 if $service{no_discount};

    $wd{total} = ( $wd{total} - $wd{total} * $wd{discount} / 100 ) * $wd{qnt};

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

    my $wd = $self->withdraw->get;
    # Already withdraw
    return 1 if $wd->{withdraw_date};

    my $user = get_service('user')->get;

    my $balance = $user->{balance} + $user->{credit};;

    # No enough money
    return 0 if (
                    $wd->{total} > 0 &&
                    $balance < $wd->{total} &&
                    !$user->{can_overdraft} &&
                    !$self->get_pay_in_credit );

    $self->user->set_balance( balance => -$wd->{total} );
    $self->withdraw->set( withdraw_date => now );
    $self->add_bonuses_for_partners( $wd->{total} );

    return 1;
}

sub add_bonuses_for_partners {
    my $self = shift;
    my $payment = shift;

    my $percent = get_service('config')->data_by_name('billing')->{partner}->{income_percent};
    return undef unless $percent;

    my $bonus = $payment * $percent / 100;

    my $user = get_service('user');
    my $partner_id_1 = $user->get_partner_id;
    return undef unless $partner_id_1;

    if ( my $partner_1 = $user->id( $partner_id_1 ) ) {
        $partner_1->set_bonus( bonus => $bonus,
            comment => {
                from_user_id => $user->id,
                percent => $percent,
            },
        );

        my $partner_id_2 = $partner_1->get_partner_id;
        return undef unless $partner_id_2;
        if ( my $partner_2 = $user->id( $partner_id_2 ) ) {
            $partner_2->set_bonus( bonus => $bonus / 2,
                comment => {
                    from_user_id => $partner_1->id,
                    percent => $percent / 2,
                },
            );
        }
    }
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

    logger->debug('Trying to prolong the service: ' . $self->id );

    if ( $self->parent_has_expired ) {
        # Не продлеваем услугу если родитель истек
        logger->debug('Parent has expired. Skipped');
        return block( $self );
    }

    # TODO: make_service_act
    # TODO: backup service

    if ( $self->get_next == -1 ) {
        # Удаляем услугу
        return remove( $self );
    }
    elsif ( $self->get_next ) {
        # Change service to new
        # TODO: change( $self );
    }

    # Для существующей услуги используем текущее/следующее/новое списание
    my $wd_id = $self->get_withdraw_id;
    my $wd = $wd_id ? get_service('wd', _id => $wd_id ) : undef;

    if ( $wd && $wd->res->{withdraw_date} ) {
        if ( my %next = $self->withdraw->next ) {
            $wd_id = $next{withdraw_id};
        } else {
            $wd_id = add_withdraw_next( $self );
        }
        $self->set( withdraw_id => $wd_id );
    }

    unless ( is_pay( $self ) ) {
        logger->debug('Not enough money');
        return block( $self );
    }

    set_service_expire( $self );
    return $self->get_status eq STATUS_BLOCK ? EVENT_ACTIVATE : EVENT_PROLONGATE;
}

sub block {
    my $self = shift;
    return 0 unless $self->get_status eq STATUS_ACTIVE;

    return EVENT_BLOCK;
}

sub activate {
    my $self = shift;
    return 0 unless $self->get_status eq STATUS_BLOCK;

    return EVENT_ACTIVATE;
}

sub remove {
    my $self = shift;

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

    $args{period_cost} ||= $service->{period_cost} // undef;
    $args{months} ||= $service->{period_cost} || 1;

    my $percent = get_service('user')->get_discount || 0;

    if ( $args{period_cost} < 2 ) {
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

    # Do not return money for domains and etc.
    return undef if $service->get->{period_cost} > 1;

    my $wd = $self->withdraw;
    return undef unless $wd;

    my %wd = $wd->get;
    return undef unless $wd{end_date};
    return undef if $wd{end_date} le $date;
    return undef if $wd{create_date} gt $date;

    my $ret = calc_total_by_date_range(
        $self->billing,
        %wd,
        end_date => $date,
    );

    my $delta = $wd{total} - $ret->{total};

    return undef if $delta < 0;

    $wd->set(
        months => $ret->{months},
        total => $ret->{total},
        end_date => $date,
    );

    $self->user->set_balance( balance => $delta );

    return $delta;
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
