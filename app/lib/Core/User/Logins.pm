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
    get_random_value
    sha256_hex
    add_period
    is_ip_allowed
);
use Data::Validate::IP qw(is_ipv4 is_ipv6);

my @TOKEN_CHARS = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
my $TOKEN_LENGTH = 64;

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
        return undef unless $obj && $self->user->id( $obj->get_user_id ); # Check exists user_id
        return $obj;
    }
    return $self->SUPER::id();
}

sub is_expired {
    my $self = shift;
    my $res = shift || $self->{res};

    my $expire_at = $res->{settings}->{expire_at} || return 0;
    return now() ge $expire_at ? 1 : 0;
}

# Аккаунт можно ограничить списком IP/подсетей (settings.allowed_ips):
# если список задан, вход разрешён только с перечисленных адресов
sub is_ip_restricted {
    my $self = shift;
    my $res = shift || $self->{res};

    my $allowed_ips = $res->{settings}->{allowed_ips};
    return 0 unless ref $allowed_ips eq 'ARRAY' && @$allowed_ips;

    return is_ip_allowed( get_user_ip(), $allowed_ips ) ? 0 : 1;
}

sub _validate_allowed_ips {
    my $ips = shift;
    return 1 unless ref $ips eq 'ARRAY' && @$ips;

    for my $ip ( @$ips ) {
        my ( $addr, $masklen ) = split '/', $ip, 2;
        return 0 unless is_ipv4( $addr ) || is_ipv6( $addr );
        return 0 if defined $masklen && $masklen !~ /^\d+$/;
    }
    return 1;
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

sub _generate_token {
    return join( '', map { get_random_value( \@TOKEN_CHARS ) } 1 .. $TOKEN_LENGTH );
}

sub add {
    my $self = shift;
    my %args = (
        login => undef,
        type => 'login',
        settings => {},
        @_,
    );

    # Логин для типа token генерируется на сервере и хранится только в виде
    # sha256-хеша, поэтому любой переданный клиентом login игнорируется
    my $plain_token;
    if ( $args{type} eq 'token' ) {
        $plain_token = _generate_token();
        $args{login} = sha256_hex( $plain_token );
        delete $args{primary};

        $args{settings} //= {};
        if ( my $ttl = $args{settings}->{ttl} ) {
            unless ( $ttl =~ /^\d+[dmyHM]$/ ) {
                report->status( 400 );
                report->add_error('Incorrect ttl format (expected e.g. 30d, 24H, 60M, 1y)' );
                return undef;
            }
            $args{settings}->{expire_at} = add_period( now(), $ttl );
        }
    } else {
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
    }

    $args{settings} //= {};

    if ( exists $args{settings}->{allowed_ips} ) {
        unless ( _validate_allowed_ips( $args{settings}->{allowed_ips} ) ) {
            report->status( 400 );
            report->add_error('Incorrect allowed_ips format (expected IP or CIDR, e.g. 1.2.3.4 or 10.0.0.0/8)' );
            return undef;
        }
    }

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

    return $ret unless $plain_token && $ret;

    # Открытый токен доступен только один раз - сразу после создания
    return {
        login    => $plain_token,
        type     => $args{type},
        user_id  => $args{user_id},
        settings => $args{settings},
    };
}

sub api_set {
    my $self = shift;
    my %args = (
        @_,
    );

    if ( ref $args{settings} eq 'HASH' && exists $args{settings}->{allowed_ips} ) {
        unless ( _validate_allowed_ips( $args{settings}->{allowed_ips} ) ) {
            report->status( 400 );
            report->add_error('Incorrect allowed_ips format (expected IP or CIDR, e.g. 1.2.3.4 or 10.0.0.0/8)' );
            return undef;
        }
    }

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
