package Core::Sessions;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( now );

sub table { return 'sessions' };

sub table_allow_insert_key { return 1 };

sub structure {
    return {
        id => {
            type => 'key',
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
    my @chars =('a' .. 'z', 0 .. 9, 'A' .. 'Z', 0 .. 9);
    my $session_id = join('', @chars[ map { rand @chars } (1 .. 32) ]);

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
    return undef unless $session_id;

    $self->_delete_expired;
    $self->res->{id} = $session_id;
    return $session_id;
}

sub validate {
    my $self = shift;
    my %args = (
        session_id => undef,
        @_,
    );

    my $session = $self->id( $args{session_id} );
    return undef unless $session;

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

sub _delete_expired {
    my $self = shift;

    $self->_delete(
        where => {
            updated => { '<', \[ 'NOW() - INTERVAL ? DAY', 1 ] },
        },
    );
}

sub delete {
    my $self = shift;

    $self->_delete_expired;
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

sub user_id {
    my $self = shift;

    return $self->res->{user_id};
}

1;
