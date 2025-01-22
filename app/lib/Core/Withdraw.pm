package Core::Withdraw;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub table { return 'withdraw_history' };

sub structure {
    return {
        withdraw_id => {
            type => 'key',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        create_date => {
            type => 'now',
        },
        withdraw_date => {
            type => 'date',
        },
        end_date => {
            type => 'date',
        },
        cost => {
            type => 'number',
            required => 1,
        },
        discount => {
            type => 'number',
            default => 0,
        },
        bonus => {
            type => 'number',
            default => 0,
        },
        months => {
            type => 'number',
            default => 1,
        },
        total => {
            type => 'number',
        },
        service_id => {
            type => 'number',
            required => 1,
        },
        qnt => {
            type => 'number',
            default => 1,
        },
        user_service_id => {
            type => 'number',
            required => 1,
        },
    }
}

sub usi {
    my $self = shift;
    return $self->{usi};
}

# Получаем предоплаченные списания (будущие периоды)
sub next {
    my $self = shift;

    unless ( $self->res->{user_service_id} ) {
        logger->fatal("Can't get next services for unknown service");
    }

    my @list = $self->list(
        where => {
            user_service_id => $self->res->{user_service_id},
            withdraw_id => { '>' => $self->id },
        },
        order => [ 'withdraw_id' => 'asc' ],
    );

    if ( wantarray ) {
        return %{ $list[0] || {} }; # Возвращаем следующий объект в виде хеша
    }

    return \@list; # Возвращаем все следующие объекты
}

sub add {
    my $self = shift;
    my %args = (
        user_service_id => $self->res->{user_service_id},
        @_,
    );

    delete $args{ $self->get_table_key };

    my $service = get_service('service', _id => $args{service_id } );
    unless ( $service ) {
        get_service('report')->add_error( "Can't create for not existed service" );
        return undef;
    }

    # Заполняем стуктуру из данных услуги, если параметр не передан явно
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

    # deduplicate user_service_id
    my %usi;
    for ( @arr ) {
        $usi{ $_->{user_service_id} } = 1 if $_->{user_service_id};
    }

    my $user_service = get_service('UserService');
    my $us = $user_service->ids(
        user_service_id => [ keys %usi ]
    )->with('settings','services')->get;

    for ( @arr ) {
        if ( exists $us->{ $_->{user_service_id} } ) {
            my $service = $us->{ $_->{user_service_id} };

            $_->{name} = get_service('service')->convert_name(
                $service->{services}->{name},
                $service->{settings},
            );
        }
        else { $_->{name} = '' };
    }
    return @arr;
}

sub found_rows {
    my $self = shift;
    my $count = shift;

    if ( defined $count ) {
        $self->{found_rows} = $count;
    }

    return $self->{found_rows};
}

sub unpaid {
    my $self = shift;

    return $self->res->{withdraw_date} ? 0 : 1;
}

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

    my $us = get_service('us', _id => $args{user_service_id} );
    unless ( $us ) {
        get_service('report')->add_error( "User service not exists" );
        return \%args;
    }

    my $service = get_service('service', _id => $args{service_id} );
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

    $us->touch;

    return $self->SUPER::api_set( %new_wd );
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
