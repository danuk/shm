package Core::SpoolHistory;

use v5.14;
use parent 'Core::Spool';
use Core::Base;

sub table { return 'spool_history' };

sub structure {
    my $self = shift;
    return {
        spool_id => '?',
        %{ $self->SUPER::structure },
        created => '?', # use date of `spool`. Do not use `now`
    }
}

sub add {
    my $self = shift;
    my %args = @_;

    $args{spool_id} = delete $args{id};

    return $self->SUPER::add( %args );
}

1;
