package Core::User::Logins;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    is_email
    is_phone
    encode_json
    now
    get_user_ip
);

sub table { return 'accounts' }
sub table_allow_insert_key { return 1 }

sub structure {
    return {
        login => {
            type  => 'text',
            key   => 1,
            title => 'логин',
        },
        type => {
            type  => 'text',
            key2  => 1,
            required => 1,
            title => 'тип логина',
            default => 'login',
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

sub id {
    my $self = shift;
    my $login = shift;
    my $types = shift || ['login','email','phone'];
    my %args = @_;

    if ( $login ) {
        my $obj = first_item $self->items(
            admin => exists $args{admin} ? $args{admin} : 1,
            where => {
                login => $login,
                ref $types eq 'ARRAY' ?
                    ( type => { '-in' => $types } ) :
                    ( type => $types ),
                defined $args{user_id} ? ( user_id => $args{user_id} ) : (),
            },
            limit => 1,
        );
        return $obj if $obj && $self->user->id( $obj->get_user_id ); # Check exists user_id
        return undef;
    }
    return $self->SUPER::id();
}

sub get {
    my $self = shift;
    my %args = (
        @_,
    );

    $args{type} ||= $self->res->{type};
    return $self->SUPER::get( %args );
}

sub set_password {
    my $self = shift;
    my $password = shift || return;

    $self->set_settings({
        password => {
            hash => $self->user->make_password( $password ),
            changed => {
                date => now(),
                ip => get_user_ip(),
            },
        },
    });
}

sub get_password {
    my $self = shift;
    return $self->settings->{password}->{hash};
}

sub items_by_types {
    my $self = shift;
    my $types = shift;

    my $where = {
        ref $types eq 'ARRAY' ?
            ( type => { '-in' => $types } ) :
            ( type => $types ),
    };

    return $self->item( where => $where );
}

sub add {
    my $self = shift;
    my %args = (
        login => undef,
        type => 'login',
        settings => {},
        @_,
    );

    $args{login} = lc $args{login};
    # Тип угадываем по виду логина только для типа по-умолчанию. У аккаунтов
    # внешних провайдеров (google_oauth2, github_oauth2, ...) логин это тоже
    # почта, и безусловная подмена превращала их в дубликат email-аккаунта
    $args{type} = 'email' if $args{type} eq 'login' && is_email( $args{login} );

    if ( $args{type} eq 'phone' ) {
        ( my $digits = $args{login} ) =~ s/\D+//g;
        $args{login} = $digits;
    }

    if ( $args{type} eq 'email' && !is_email( $args{login} ) ) {
        report->status( 400 );
        report->add_error('Incorrect login format (is not email)' );
        return undef;
    }

    if ( $args{type} eq 'phone' && !is_phone( $args{login} ) ) {
        report->status( 400 );
        report->add_error('Incorrect login format (is not phone)' );
        return undef;
    }

    $args{settings} //= {};
    $args{settings}->{created} = {
        date => now(),
        ip => get_user_ip,
    };

    my $ret = $self->SUPER::add( %args );
    if ( $ret ) {
        if ( $args{primary} ) {
            $self->user->set(
                login => $args{login},
            );
        }
    }
    return $ret;
}

sub api_set {
    my $self = shift;
    my %args = (
        @_,
    );

    my %ret = $self->SUPER::api_set( %args );
    return undef unless %ret;

    if ( $args{primary} ) {
        # Если этот логин уже является primary у другого пользователя - снимаем его оттуда
        my $other_users = $self->user->items(
            admin => 1,
            where => {
                login => $args{login},
                user_id => { '!=' => $self->user_id },
            },
        );
        $_->set( login => '' ) for @$other_users;

        $self->user->set(
            login => $args{login},
        );
    }

    $self->set_password( $args{password} ) if $args{password};

    return %ret;
}

sub is_primary {
    my $self = shift;
    my $res = shift || $self->{res};

    return 0 unless $res->{user_id};
    my $user = $self->user->id( $res->{user_id} ) || return 0;

    return lc($res->{login}) eq lc($user->get_login) ? 1 : 0;
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        filter => {},
        where => {},
        @_,
    );

    my @list = $self->SUPER::list_for_api( %args );
    $self->{_found_rows_cache} = $self->SUPER::found_rows();

    for ( @list ) {
        $_->{primary} = $self->is_primary( $_ );
    }

    return @list;
}

sub found_rows {
    my $self = shift;
    return exists $self->{_found_rows_cache}
        ? delete( $self->{_found_rows_cache} )
        : $self->SUPER::found_rows();
}

sub api_delete {
    my $self = shift;
    my %args = (
        login => undef,
        type => undef,
        @_,
    );

    return { error => 1 } unless $args{login} && $args{type};

    $self->delete(
        where => {
            login => $args{login},
            type => $args{type},
        },
    );

    $self->user->set( login => '' );

    return { success => 1 };
}

1;
