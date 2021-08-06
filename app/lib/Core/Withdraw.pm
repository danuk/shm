package Core::Withdraw;

use v5.14;
use parent 'Core::Base';
use Core::Base;

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

sub _id {
    my $self = shift;
    return $self->id ? 'wd_'.$self->id : 'wd';
}

sub usi {
    my $self = shift;
    return $self->{usi} || confess("usi not defined");
}

# Получаем предоплаченные списания (будущие периоды)
sub next {
    my $self = shift;

    unless ( $self->res->{user_service_id} ) {
        logger->error("Can't get next services for unknown service");
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

    my $service = get_service('service', _id => $args{service_id } );
    unless ( $service ) {
        get_service('report')->add_error( "Can't create for not existed service" );
        return undef;
    }

    # Заполняем стуктуру из данных услуги, если параметр не передан явно
    my $srv = $service->get;
    for ( keys %{ $srv } ) {
        $args{ $_ }||= $srv->{ $_ };
    }

    return $self->SUPER::add( %args );
}

sub list {
    my $self = shift;
    my %args = @_;

    if ( $self->{usi} ) {
        $args{where}->{user_service_id} = $self->{usi};
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
        $_->{discount_date} = $_->{withdraw_date};
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

1;
