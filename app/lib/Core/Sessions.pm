package Core::Sessions;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( now );

sub table { return 'sessions' };

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
        settings => { type => 'json', value => undef },
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
        user_id => undef,
        @_,
    );

    my $session_id = $self->SUPER::add( %args );
    return undef unless $session_id;

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

sub user_id {
    my $self = shift;

    return $self->res->{user_id};
}

1;
