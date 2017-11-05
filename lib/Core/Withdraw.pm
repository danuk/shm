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


sub usi {
    my $self = shift;
    return $self->{usi} || confess("usi not defined");
}

# Получаем предоплаченные списания (будущие периоды)
sub next {
    my $self = shift;

    my @vars;
    my $query = $self->query_select(    vars => \@vars,
                                        user_id => $self->user_id,
                                        order => [ 'withdraw_id' => 'asc' ],
                                        where => { user_service_id => $self->usi, withdraw_id => $self->id },
    );

    my $res = $self->query( $query, @vars );

    if ( wantarray ) {
        return %{ $res->[0]||={} }; # Возвращаем следующий объект в виде хеша
    }

    return $res || []; # Возвращаем все следующие объекты
}

sub add {
    my $self = shift;
    my %args = (
        user_id => $self->user_id,
        user_service_id => $self->{usi},
        @_,
    );

    # Заполняем стуктуру из данных услуги, если параметр не передан явно
    my $srv = get_service('service', _id => $args{service_id } )->get;
    for ( keys %{ $srv } ) {
        $args{ $_ }||= $srv->{ $_ };
    }

    $self->{withdraw_id} = $self->SUPER::add( %args );
    return $self;
}

sub list_for_api {
    my $self = shift;
    my @arr = $self->SUPER::list_for_api( field => 'withdraw_date', @_ );

    my $us = get_service('UserServices')->ids(
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
