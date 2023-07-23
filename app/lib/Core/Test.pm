package Core::Test;

use v5.14;
use parent 'Core::Base';

sub list_for_api {
    my $self = shift;

    return { test => 'OK' };
}

sub test_post {
    my $self = shift;
    my %args = @_;

    return {
        payload => \%args,
    };
}

1;

