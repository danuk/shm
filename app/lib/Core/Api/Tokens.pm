package Core::Api::Tokens;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( now );
use Digest::SHA qw( sha256_hex );
use Core::Utils qw( decode_json print_header print_json );

sub table { return 'api_tokens' };
sub dbh { my $self = shift; $self->{_autocommit_dbh} ||= $self->dbh_new( AutoCommit => 1, InactiveDestroy => 0 ); return $self->{_autocommit_dbh}; }

sub table_allow_insert_key { return 0 };

sub structure {
    return {
        id => {
            type => 'number',
            key  => 1,
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        token => {
            type      => 'text',
            hide_for_user => 1,
        },
        name => {
            type => 'text',
        },
        scopes => {
            type  => 'json',
            value => {},
        },
        expires => {
            type => 'text',
        },
        last_used => {
            type => 'text',
        },
        is_active => {
            type  => 'number',
            value => 1,
        },
        created => {
            type => 'text',
        },
    }
}

sub generate_token {
    my $raw;
    open( my $fh, '<:raw', '/dev/urandom' ) or die "Cannot open /dev/urandom: $!";
    read( $fh, $raw, 32 );
    close $fh;
    return sha256_hex($raw);
}

sub create_token {
    my $self = shift;
    my %args = (
        name      => undef,
        scopes    => {},
        expires   => undef,
        @_,
    );

    my $plain_token  = $self->generate_token();
    my $stored_token = sha256_hex($plain_token);

    my $id = $self->SUPER::add(
        token     => $stored_token,
        name      => $args{name},
        scopes    => $args{scopes},
        expires   => $args{expires},
        is_active => 1,
        created   => now(),
    );

    return {
        id    => $id,
        token => $plain_token,
    };
}

sub validate {
    my $self = shift;
    my %args = (
        token => undef,
        @_,
    );

    return undef unless $args{token};

    my $stored = sha256_hex( $args{token} );

    my ($row) = $self->_list(
        fields => 'id,user_id,scopes,expires,is_active',
        where  => { token => $stored },
        limit  => 1,
    );

    return undef unless $row;
    return undef unless $row->{is_active};

    if ( $row->{expires} ) {
        my $now = now();
        return undef if $row->{expires} lt $now;
    }

    $self->_set(
        last_used => now(),
        where     => { id => $row->{id} },
    );

    return $row;
}

sub check_scope {
    my ( $self, $token_row, $route, $http_method ) = @_;

    my $scopes = $token_row->{scopes};
    return 0 unless ref $scopes eq 'HASH';

    $route =~ s{^/}{};
    $route = lc $route;

    my $allowed_actions = $scopes->{ $route };
    return 0 unless $allowed_actions && ref $allowed_actions eq 'ARRAY';

    my %method_to_action = (
        GET    => 'get',
        POST   => 'post',
        PUT    => 'put',
        DELETE => 'delete',
    );

    my $required_action = $method_to_action{ uc $http_method } // return 0;

    return grep { $_ eq $required_action } @{ $allowed_actions };
}

# Api methods
sub list_for_api {
    my $self = shift;

    return $self->_list(
        fields => 'id,name,scopes,expires,last_used,is_active,created',
        where  => {},
        order  => ['created', 'desc'],
    );
}

sub api_add {
    my $self = shift;
    my %args = (
        name    => undef,
        scopes  => undef,
        expires => undef,
        @_,
    );

    my $scopes = $args{scopes};
    if ( defined $scopes && !ref $scopes ) {
        $scopes = eval { decode_json($scopes) };
        return _error( 400, 'scopes must be a valid JSON object' ) if $@ || !defined $scopes;
    }
    $scopes //= {};
    return _error( 400, 'scopes must be a JSON object' ) unless ref $scopes eq 'HASH';

    my %valid_actions = map { $_ => 1 } qw( get post put delete );
    for my $route ( keys %$scopes ) {
        my $actions = $scopes->{$route};
        return _error( 400, "scopes.$route must be an array" ) unless ref $actions eq 'ARRAY';
        for my $action ( @$actions ) {
            return _error( 400, "Unknown action '$action'. Allowed: get, post, put, delete" )
                unless $valid_actions{$action};
        }
    }

    my $result = $self->create_token(
        name    => $args{name},
        scopes  => $scopes,
        expires => $args{expires} || undef,
    );

    return $result;
}

sub api_set {
    my $self = shift;
    my %args = (
        id        => undef,
        name      => undef,
        scopes    => undef,
        expires   => undef,
        is_active => undef,
        @_,
    );

    return _error( 400, 'id required' ) unless $args{id};

    my %update;
    $update{name}      = $args{name}      if defined $args{name};
    $update{expires}   = $args{expires}   if defined $args{expires};
    $update{is_active} = $args{is_active} if defined $args{is_active};

    if ( defined $args{scopes} ) {
        my $scopes = $args{scopes};
        if ( !ref $scopes ) {
            $scopes = eval { decode_json($scopes) };
            return _error( 400, 'scopes must be a valid JSON object' ) if $@ || !defined $scopes;
        }
        return _error( 400, 'scopes must be a JSON object' ) unless ref $scopes eq 'HASH';
        $update{scopes} = $scopes;
    }

    return _error( 400, 'No fields to update' ) unless %update;

    $self->_set(
        %update,
        where => { id => $args{id} },
    );

    return { id => $args{id}, updated => 1 };
}

sub delete {
    my $self = shift;
    my %args = (
        id => undef,
        @_,
    );

    return _error( 400, 'id required' ) unless $args{id};

    $self->_delete(
        where => { id => $args{id} },
    );

    return { id => $args{id}, deleted => 1 };
}

sub _error {
    my ( $code, $msg ) = @_;
    print_header( status => $code );
    print_json( { status => $code, error => $msg } );
    exit 0;
}

1;
