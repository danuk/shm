package Core::Console;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw/now/;

sub table { return 'console' };

sub structure {
    return {
        id => {
            type => 'number',
            key => 1,
        },
        start => {
            type => 'now',
        },
        stop => {
            type => 'date',
        },
        log => {
            type => 'text',
            default => '',
        },
        eof => {
            type => 'number',
            default => 0,
        },
    }
}

sub new_pipe {
    my $self = shift;

    return $self->add();
}

sub append {
    my $self = shift;
    my $log = shift;

    utf8::downgrade( $log );

    $self->do("UPDATE ".$self->table." SET log = CONCAT(log, ?) WHERE id=?",
        $log,
        $self->id,
    );
}

sub set_eof {
    my $self = shift;

    $self->set( eof => 1, stop => now );
}

sub chunk {
    my $self = shift;
    my %args = (
        offset => 1,
        @_,
    );

    my ( $res ) = $self->query("SELECT id,eof,SUBSTRING(log,?) as chunk FROM ".$self->table." WHERE id=?",
        $args{offset},
        $self->id,
    );

    $self->res( $res );

    utf8::decode($res->{chunk});
    return $res->{chunk};
}

sub eof {
    my $self = shift;

    return $self->get->{eof};
}

sub clean {
    my $self = shift;
    my %args = (
        days => 30,
        get_smart_args( @_ ),
    );

    return $self->_delete( where => {
        start => { '<', \[ 'NOW() - INTERVAL ? DAY', 30 ] },
    });
}

1;
