package Core::Test;

use v5.14;
use parent 'Core::Base';

sub list_for_api {
    my $self = shift;

    return { test => 'OK' };
}

1;

