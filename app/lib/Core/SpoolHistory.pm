package Core::SpoolHistory;

use v5.14;
use parent 'Core::Spool';
use Core::Base;

sub table { return 'spool_history' };
sub dbh { shift->dbh_myisam };

sub structure {
    my $self = shift;
    return {
        spool_id => {
            type => 'number',
            required => 1,
            title => 'id архивной задачи',
        },
        %{ $self->SUPER::structure },
        created => {    # use date of `spool`. Do not use `now`
            type => 'date',
            required => 1,
        },
    }
}

sub add {
    my $self = shift;
    my %args = @_;

    $args{spool_id} = delete $args{id};

    return $self->SUPER::add( %args );
}

sub cleanup {
    my $self = shift;
    my $days = cfg('billing')->{cleanup}->{ $self->kind } // 30;
    return $self unless $days;

    $self->srv('console')->cleanup( days => $days );

    $self->_delete( where => {
        executed => { '<', \[ 'NOW() - INTERVAL ? DAY', $days ] },
    });

    return $self;
}

1;
