package Core::Sessions;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( now random_bytes get_user_ip get_user_agent sha256_hex );

sub table { return 'sessions' };
sub dbh { shift->dbh_auto_commit };

sub table_allow_insert_key { return 1 };

# Maps internal fingerprint field names to their cfg('session')->{strict}
# config key, so IP and User-Agent enforcement can be toggled independently.
my %STRICT_CFG_KEY = (
    ip         => 'ip',
    user_agent => 'user-agent',
);

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

sub hash_id {
    my $self = shift;
    my $id = shift;
    return sha256_hex( $id );
}

sub add {
    my $self = shift;
    my %args = (
        id => _generate_id(),
        user_id => $self->SUPER::user_id,
        @_,
    );

    # Snapshot the current session security policy (strict IP/User-Agent
    # enforcement flags) and bind the creating client's fingerprint right
    # away, so that:
    #  - a later change to cfg('session')->{strict} doesn't retroactively
    #    alter the enforcement of sessions that are already active;
    #  - validate() has a fingerprint to compare against from the very
    #    first request, not just once bind_fingerprint() happens to be
    #    called elsewhere.
    my $cfg_strict = cfg('session')->{strict} || {};
    $cfg_strict->{'user-agent'} = 1; # Force strict User-Agent

    $args{settings} = {
        %{ $args{settings} || {} },
        ip         => get_user_ip(),
        user_agent => get_user_agent(),
        strict     => { map { $_ => ( $cfg_strict->{ $_ } ? 1 : 0 ) } values %STRICT_CFG_KEY },
    };

    # The plain session_id is the bearer credential handed to the client
    # (cookie/API response); only its sha256 hash is ever persisted.
    my $session_id = $args{id};
    $args{id} = $self->hash_id( $session_id );

    return undef unless $self->SUPER::add( %args );

    $self->res->{id} = $session_id;

    return $session_id;
}

sub bind_fingerprint {
    my $self = shift;
    my %args = (
        session_id => undef,
        @_,
    );

    my $session = $args{session_id} ? $self->id( $self->hash_id( $args{session_id} ) ) : $self;
    return undef unless $session;

    my $settings = $session->settings || {};

    # Pin the session to the client fingerprint (IP + User-Agent) seen on
    # first use. Once bound, these values are never overwritten, so
    # validate() can detect a session_id replayed by a different client
    # (e.g. stolen/intercepted session_id).
    return $session if $settings->{ip} || $settings->{user_agent};

    # This path is only taken for routes that accept `session_id` as an
    # explicit request parameter (QR-code/cross-device login flows etc.),
    # which is inherently more exposed to interception than a cookie. Force
    # strict enforcement for this binding, regardless of the global
    # cfg('session')->{strict} setting, so any fingerprint mismatch
    # immediately invalidates the session.
    return $session->set( settings => {
        %{ $settings },
        ip         => get_user_ip(),
        user_agent => get_user_agent(),
        strict     => { map { $_ => 1 } values %STRICT_CFG_KEY },
    } );
}

# Checks the current request against the fingerprint bound to the session.
# Returns the list of mismatching field names (ip, user_agent), or an empty
# list if everything matches (or no fingerprint was ever bound).
sub _fingerprint_mismatches {
    my $self = shift;
    my $session = shift;

    my $settings = $session->settings || {};
    my @mismatches;

    push @mismatches, 'ip' if $settings->{ip} && $settings->{ip} ne get_user_ip();
    push @mismatches, 'user_agent' if $settings->{user_agent} && $settings->{user_agent} ne get_user_agent();

    return @mismatches;
}

sub validate {
    my $self = shift;
    my %args = (
        session_id => undef,
        @_,
    );

    return undef unless $args{session_id};
    my $hashed_id = $self->hash_id( $args{session_id} );

    my $session = $self->id( $hashed_id );
    return undef unless $session;

    # A fingerprint mismatch (IP and/or User-Agent changed since creation/
    # bind_fingerprint) is suspicious, but IP in particular can legitimately
    # change (mobile networks, roaming proxies). Enforcement is governed by
    # the `strict` flags snapshotted into the session's own settings at
    # creation time (see add()) rather than the live config, so a later
    # change to cfg('session')->{strict} doesn't retroactively affect
    # sessions that are already active. By default (no snapshot / flag off)
    # a mismatch is only logged.
    my @mismatches = $self->_fingerprint_mismatches( $session );
    if ( @mismatches ) {
        my $strict = $session->settings->{strict} || {};

        for my $field ( @mismatches ) {
            my $strict_key = $STRICT_CFG_KEY{ $field };
            if ( $strict->{ $strict_key } ) {
                logger->warning("Session $hashed_id rejected: $field mismatch");
                return undef;
            }
            logger->warning("Session $hashed_id $field mismatch ignored (session strict.$strict_key is disabled)");
        }
    }

    # do not update more than 3 minutes
    $self->_set(
        updated => now,
        where => {
            id => $hashed_id,
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
