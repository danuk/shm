package Core::Withdraw;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub table { return 'withdraw_history' };

sub structure {
    return {
        withdraw_id => {
            type => 'number',
            key => 1,
            title => 'id списания',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
            title => 'id пользователя',
        },
        create_date => {
            type => 'now',
            title => 'дата создания списания',
            readOnly => 1,
        },
        withdraw_date => {
            type => 'date',
            title => 'дата списания',
            readOnly => 1,
        },
        end_date => {
            type => 'date',
            title => 'дата окончания',
            readOnly => 1,
        },
        cost => {
            type => 'number',
            required => 1,
            title => 'стоимость',
        },
        discount => {
            type => 'number',
            default => 0,
            title => 'скидка',
        },
        bonus => {
            type => 'number',
            default => 0,
            title => 'кол-во бонусов',
        },
        months => {
            type => 'number',
            default => 1,
            title => 'период',
        },
        total => {
            type => 'number',
            title => 'итоговая стоимость',
        },
        service_id => {
            type => 'number',
            required => 1,
            title => 'id услуги',
        },
        qnt => {
            type => 'number',
            default => 1,
            title => 'кол-во',
        },
        user_service_id => {
            type => 'number',
            required => 1,
            title => 'id услуги пользователя',
        },
    }
}

sub usi {
    my $self = shift;
    return $self->{usi} || $self->get_user_service_id;
}

# Получаем предоплаченные списания (будущие периоды)
sub next {
    my $self = shift;

    my @list;

    if ( my $usi = $self->usi ) {
        @list = $self->list(
            where => {
                user_service_id => $usi,
                withdraw_id => { '>' => $self->id },
            },
            order => [ 'withdraw_id' => 'asc' ],
        );
    }

    if ( wantarray ) {
        return %{ $list[0] || {} }; # Возвращаем следующий объект в виде хеша
    }

    return \@list; # Возвращаем все следующие объекты
}

sub add {
    my $self = shift;
    my %args = (
        user_service_id => $self->usi,
        @_,
    );

    unless ( $args{user_service_id} ) {
        get_service('report')->add_error( "Can't create withdraw without user_service_id" );
        return undef;
    }

    delete $args{ $self->get_table_key };

    my $service = $self->srv('service', _id => $args{service_id} );
    unless ( $service ) {
        get_service('report')->add_error( "Can't create for not existed service" );
        return undef;
    }

    # Заполняем структуру из данных услуги, если параметр не передан явно
    my $srv = $service->get;
    for ( keys %{ $srv } ) {
        $args{ $_ }//= $srv->{ $_ };
    }

    return $self->SUPER::add( %args );
}

sub list {
    my $self = shift;
    my %args = @_;

    if ( $self->usi ) {
        $args{where}->{user_service_id} = $self->usi;
    }

    return $self->SUPER::list( order => [ $self->get_table_key => 'asc' ], %args );
}

sub list_for_api {
    my $self = shift;
    my @arr = $self->SUPER::list_for_api( field => 'withdraw_date', @_ );
    $self->found_rows( $self->SUPER::found_rows() );

    for ( @arr ) {
        if ( my $service = get_service('service', _id => $_->{service_id} ) ) {
            $_->{name} = $service->get_name;
        } else {
            $_->{name} = '';
        }
    }
    return @arr;
}

sub last {
    my $self = shift;

    my $pay = first_item $self->rsort('withdraw_date')->items(
        limit => 1,
    );

    return $pay;
}

sub found_rows {
    my $self = shift;
    my $count = shift;

    if ( defined $count ) {
        $self->{found_rows} = $count;
    }

    return $self->{found_rows};
}

sub paid {
    my $self = shift;
    return $self->get_withdraw_date ? 1 : 0;
}
sub unpaid { $_[0]->paid ? 0 : 1 };

*delete = \&delete_unpaid;

sub delete_unpaid {
    my $self = shift;
    my $usi = shift || $self->usi;

    return undef unless $usi;

    return $self->SUPER::_delete(
        where => {
            user_id => $self->user_id,
            user_service_id => $usi,
            withdraw_date => undef,
        },
    );
}

sub api_set {
    my $self = shift;
    my %args = (
        @_,
    );

    my $us = $self->srv('us', _id => $args{user_service_id} );
    unless ( $us ) {
        get_service('report')->add_error( "User service not exists" );
        return \%args;
    }

    my $service = $self->srv('service', _id => $args{service_id} );
    unless ( $service ) {
        get_service('report')->add_error( "Service not exists" );
        return \%args;
    }

    if ( $us->get_withdraw_id != $self->id && $us->get_expire ) {
        get_service('report')->add_error( "This item cannot be edited because it is from the past" );
        return \%args;
    }

    use Core::Billing;
    my %wd = $self->get;
    my %new_wd = calc_withdraw( $us->billing, $service->get, %wd, %args );

    # Always forbid set/change withdraw_date because of it makes by spool
    delete $new_wd{withdraw_date};

    if ( $us->get_withdraw_id == $self->id && $us->get_status eq STATUS_ACTIVE ) {
        $us->set( expire => $new_wd{end_date} );
    } else {
        # Forbid set end_date for non active user service
        delete $new_wd{end_date};
    }

    if ( $wd{total} != $new_wd{total} ) {
        unless ( $self->unpaid ) {
            $self->user->set_balance(
                balance => $wd{total} - ( $new_wd{total} - $new_wd{bonus} ),
            );
        }
    }

    if ( $wd{bonus} != $new_wd{bonus} ) {
        $self->user->set_bonus(
            bonus => $wd{bonus} - $new_wd{bonus},
            comment => { comment => sprintf("changed withdraw %d by admin", $self->id) },
        );
    }

    my $ret = $self->SUPER::api_set( %new_wd );
    $us->touch;

    return $ret;
}

sub sum {
    my $self = shift;
    my %args = (
        where => {},
        @_,
    );

    $args{where}{withdraw_date} ||= {'!=' => undef };

    return $self->SUPER::sum( %args );
}

1;
