package Core::User::Logins;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    is_email
    encode_json
    now
    get_user_ip
);

sub table { return 'logins' }
sub table_allow_insert_key { return 1 }

sub structure {
    return {
        login => {
            type  => 'text',
            key   => 1,
            title => 'логин',
        },
        user_id => {
            type     => 'number',
            required => 1,
            auto_fill => 1,
            hide_for_user => 1,
            title    => 'id пользователя',
        },
        settings => {
            type  => 'json',
            value => {},
            title => 'настройки логина',
            hide_for_user => 1,
        },
    };
}

sub set_password {
    my $self = shift;
    my $password = shift || return;

    $self->set_settings(
        password => {
            hash => $password,
            changed => {
                date => now(),
                ip => get_user_ip(),
            },
        },
    );
}

sub get_password {
    my $self = shift;
    return $self->settings->{password}->{hash};
}

sub list_by_user {
    my $self = shift;
    return $self->list();
}

sub add {
    my $self = shift;
    my %args = (
        login => undef,
        settings => {},
        @_,
    );

    $args{login} = lc $args{login};

    $args{settings} //= {};
    $args{settings}->{created} = {
        date => now(),
        ip => get_user_ip,
    };

    return $self->SUPER::add( %args );
}

sub api_delete {
    my $self = shift;
    my %args = (
        login => undef,
        @_,
    );

    return undef $args{login};

    $self->delete( where => { login => $args{login} } );

    return { success => 1 };
}

1;
