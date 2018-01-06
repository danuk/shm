package Core::ServicesCategories;

use v5.14;
use parent 'Core::ServicesCommands';

sub list {
    my $self = shift;
    return $self->query('SELECT category FROM ' . $self->table . ' GROUP by category');
}

1;
