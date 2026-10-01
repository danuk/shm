package Core::Sessions;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( now random_bytes get_user_ip );

sub table { return 'sessions' };
sub dbh { shift->dbh_auto_commit };

sub table_allow_insert_key { return 1 };

sub structure {
    return {
        id => {
            type => 'text',
            key => 1,
        },
        user_id => {
            type => 'number',
        },
        created => {
            type => 'text',
        },
        updated => {
            type => 'text',
        },
        settings => { type => 'json', value => {} },
    }
}

sub _generate_id {
    my @chars = ('a' .. 'z', 'A' .. 'Z', '0' .. '9');
    my $n = scalar @chars;
    my $session_id = '';
    while ( length($session_id) < 32 ) {
        for my $byte ( unpack( 'C*', random_bytes(64) ) ) {
            next if $byte >= int( 256 / $n ) * $n;  # rejection sampling — uniform distribution
            $session_id .= $chars[ $byte % $n ];
            last if length($session_id) == 32;
        }
    }
    return $session_id;
}

sub add {
    my $self = shift;
    my %args = (
        id => _generate_id(),
        user_id => $self->SUPER::user_id,
        @_,
    );

    my $session_id = $self->SUPER::add( %args );

    $self->res->{id} = $session_id;

    return $session_id;
}

sub bind_ip {
    my $self = shift;
    my %args = (
        session_id => undef,
        @_,
    );

    my $session = $args{session_id} ? $self->id( $args{session_id} ) : $self;
    return undef unless $session;

    # Pin the session to the IP that first used it. Once bound, the IP is
    # never overwritten, so validate() will reject the session_id if it is
    # later replayed from a different IP (e.g. stolen/intercepted session_id).
    return $session if $session->settings->{ip};

    return $session->set( settings => { %{ $session->settings || {} }, ip => get_user_ip() } );
}

sub validate {
    my $self = shift;
    my %args = (
        session_id => undef,
        @_,
    );

    my $session = $self->id( $args{session_id} );
    return undef unless $session;

    # if an IP address was stored for this session, it must match the current one
    my $session_ip = $session->settings->{ip};
    if ( $session_ip && $session_ip ne get_user_ip() ) {
        return undef;
    }

    # do not update more than 3 minutes
    $self->_set(
        updated => now,
        where => {
            id => $args{session_id},
            updated => { '<', \[ 'NOW() - INTERVAL ? MINUTE', 3 ] },
        },
    );

    return $session;
}

sub cleanup {
    my $self = shift;

    $self->_delete(
        where => {
            updated => { '<', \[ 'NOW() - INTERVAL ? DAY', 3 ] },
        },
    );
    return $self;
}

sub delete {
    my $self = shift;
    $self->SUPER::delete( @_ );
}

sub delete_user_sessions {
    my $self = shift;
    my %args = (
        user_id => undef,
        @_,
    );

    return undef unless $args{user_id};

    return $self->_delete(
        where => {
            user_id => $args{user_id},
        },
    );
}

sub delete_all {
    my $self = shift;

    return $self->SUPER::_delete(
        where => {
            user_id => $self->SUPER::user_id,
        },
    );
}

1;
