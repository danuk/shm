package Core::Billing;

use v5.14;
use Carp qw(confess);

use base qw(
    Core::Pay
    Core::User
);

use base qw(Exporter);

our @EXPORT = qw(
    create_service
    process_service_recursive
);

use Core::Const;
use Core::Utils qw(now string_to_utime utime_to_string start_of_month end_of_month parse_date days_in_months);
use Time::Local 'timelocal_nocheck';

use base qw( Core::System::Service );
use Core::System::ServiceManager qw( get_service logger );

use Core::Billing::Honest;

sub awaiting_payment {
    my $self = shift;

    return 1 if (   $self->get_status == STATUS_BLOCK ||
                    $self->get_status == STATUS_WAIT_FOR_PAY );
    return 0;
}

sub create_service {
    my %args = (
        service_id => undef,
        @_,
    );

    for ( keys %args ) {
        unless ( defined $args{ $_ } ) {
            logger->error( "Not exists `$_` in args" );
        }
    }

    my $us = get_service('UserServices')->add( service_id => $args{service_id} );

    my $wd_id = get_service('wd')->add( calc_withdraw(%args), user_service_id => $us->id );
    $us->set( withdraw_id => $wd_id );

    my $ss = get_service('service', _id => $args{service_id} )->subservices;
    for ( keys %{ $ss } ) {
        get_service('UserServices')->add( service_id => $ss->{ $_ }->{subservice_id}, parent => $us->id );
    }

    return process_service_recursive( $us, EVENT_CREATE );
}

sub process_service_recursive {
    my $service = shift;
    my $event = shift || EVENT_PROLONGATE;

    # Дети наследуют событие родителя
    if ( $event = process_service( $service, $event ) ) {
        # Вызываем событие в услуге
        $service->event( $event );

        for my $child ( $service->children ) {
            process_service_recursive(
                get_service('us', _id => $child->{user_service_id} ),
                $event,
            );
        }
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

    logger->debug('Process service: '. $self->id );

    unless ( $self->get_withdraw_id ) {
        # Бесплатная услуга
        return $event;
    }

    unless ( $self->get_auto_bill ) {
        logger->debug('AUTO_BILL is OFF for service. Skipping...');
        return undef;
    }

    unless ( $self->get_expired ) {
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

# Создание следущего платежа на основе текущего
sub add_withdraw_next {
    my $self = shift;

    my $wd = $self->withdraws->get;

    my %wd = calc_withdraw(
        %{ $wd },
        months => int $wd->{months},
        bonus => 0,
    );

    return $self->withdraws->add( %wd );
}

# Вычисляет итоговую стоимость услуги
# на вход принимает все аргументы списания
sub calc_withdraw {
    my %wd = (
        cost => undef,
        months => 1,
        discount => 0,
        qnt => 1,
        @_,
    );

    for ( qw/ cost months discount qnt / ) {
        unless ( defined $wd{ $_ } ) {
            logger->error( "Not exists `$_` in wd object" );
        }
    }

    # Вычисляем реальное кол-во месяцов для правильного подсчета стоимости
    my $period_cost = get_service( 'service', _id => $wd{service_id} )->get->{period_cost};

    if ( $wd{months} < $period_cost ) {
        $wd{months} = $period_cost;
    }

    my $real_payment_months = sprintf("%.2f", $wd{months} / ($period_cost || 1) );

    $wd{withdraw_date}||= now;
    $wd{end_date} = calc_end_date_by_months( $wd{withdraw_date}, $real_payment_months );

    $wd{total} = calc_total_by_date_range( %wd );
    $wd{discount} = get_service_discount( %wd );

    $wd{total} = ( $wd{total} - $wd{total} * $wd{discount} / 100 ) * $wd{qnt};

    $wd{total} -= $wd{bonus};

    return %wd;
}

sub is_pay {
    my $self = shift;

    return undef unless $self->get_withdraw_id;

    my $wd = $self->withdraws->get;
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
    $self->withdraws->set( withdraw_date => now );

    return 1;
}

sub set_service_expire {
    my $self = shift;

    my $wd = $self->withdraws->get;
    my $now = now;

    if ( $self->get_expired && $self->get_status != STATUS_BLOCK ) {
        # Услуга истекла (не новая) и не заблокирована ранее
        # Будем продлять с момента истечения
        $now = $self->get_expired;
    }

    my $expire_date = calc_end_date_by_months( $now, $wd->{months} );

    #if ( $config->{child_expired_by_parent} {
    #if ( my $parent_expire_date = parent_has_expired( $self ) ) {
    #     if ( $expire_date gt $parent_expire_date ) {
    #        # дата истечения услуги не должна быть больше чем дата истечения родителя
    #        $expire_date = $parent_expire_date;
    #        # TODO: cacl and set real months
    #    }
    #}}

    $self->withdraws->set( end_date => $expire_date );

    return $self->set( expired => $expire_date );
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

    logger->debug('Trying prolongate service:' . $self->id );

    if ( $self->parent_has_expired ) {
        # Не продлеваем услугу если родитель истек
        logger->debug('Parent expired. Skipped');
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
        if ( my %next = $self->withdraws->next ) {
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
    return $self->get_status == STATUS_BLOCK ? EVENT_ACTIVATE : EVENT_PROLONGATE;
}

sub block {
    my $self = shift;
    return 0 unless $self->get_status == STATUS_ACTIVE;
    return EVENT_BLOCK;
}

sub remove {
    my $self = shift;
    return EVENT_REMOVE;
}

# Анализируем услугу и решаем какую скидку давать (доменам не давать)
# более 50% не давать
sub get_service_discount {
    my %args = (
        months => undef,
        service_id => undef,
        @_,
    );

    my $service = $args{service_id} ? get_service( 'service', _id => $args{service_id} )->get : {};

    $args{period_cost} ||= $service->{period_cost} // undef;
    $args{months} ||= $service->{period_cost} || 1;

    for ( keys %args ) {
        unless ( defined $args{ $_ } ) {
            logger->error("not defined required variable: $_");
        }
    }

    my $percent = get_service('user')->get_discount || 0;

    if ( $args{period_cost} < 2 ) {
        # Вычисляем скидку за кол-во месяцев
        my $discount_info = get_service('discounts')->get_by_period( months => $args{months} );
        if ( $discount_info ) {
            $percent += $discount_info->{percent};
        }
    }

    $percent = 50 if $percent > 50;
    return $percent;
}

1;
