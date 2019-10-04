package Core::Withdraw;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'withdraw_history' };

sub structure {
    return {
        withdraw_id => '@',
        user_id => '!',
        create_date => 'now',
        withdraw_date => undef,
        end_date => undef,
        cost => '?',
        discount => 0,
        bonus => 0,
        months => 1,
        total => undef,
        service_id => '?',
        qnt => 1,
        user_service_id => '?',
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

    unless ( $args{user_service_id} ) {
        logger->error('`user_service_id` required');
    }

    delete @args{ qw/end_date withdraw_date/ };

    # Заполняем стуктуру из данных услуги, если параметр не передан явно
    my $srv = get_service('service', _id => $args{service_id } )->get;
    for ( keys %{ $srv } ) {
        $args{ $_ }||= $srv->{ $_ };
    }

    return $self->SUPER::add( %args );
}

sub list {
    my $self = shift;
    my %args = @_;
    return $self->SUPER::list( order => [ $self->get_table_key => 'asc' ], %args );
}

sub list_for_api {
    my $self = shift;
    my @arr = $self->SUPER::list_for_api( field => 'withdraw_date', @_ );

    my $us = get_service('UserService')->ids(
        user_service_id => [ map $_->{user_service_id}, @arr ]
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

1;
