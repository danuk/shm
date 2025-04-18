package Core::SpoolHistory;

use v5.14;
use parent 'Core::Spool';
use Core::Base;

sub table { return 'spool_history' };

sub structure {
    my $self = shift;
    return {
        spool_id => {
            type => 'number',
            required => 1,
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

sub clean {
    my $self = shift;
    my %args = (
        days => 30,
        get_smart_args( @_ ),
    );

    $self->srv('console')->clean( days => $args{days} );

    return $self->_delete( where => {
        executed => { '<', \[ 'NOW() - INTERVAL ? DAY', 30 ] },
    });
}

1;
