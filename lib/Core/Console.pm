package Core::Console;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'console' };

sub structure {
    return {
        id => '@',
        log => '',
        eof => 0,
    }
}

sub new_pipe {
    my $self = shift;

    return $self->add();
}

sub append {
    my $self = shift;
    my $log = shift;

    $self->do("UPDATE ".$self->table." SET log = CONCAT(log, ?) WHERE id=?",
        $log,
        $self->id,
    );
}

sub set_eof {
    my $self = shift;

    $self->set( eof => 1 );
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

    return $res->{chunk};
}

sub eof {
    my $self = shift;

    return $self->get->{eof};
}

1;
