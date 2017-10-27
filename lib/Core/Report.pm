package Core::Report;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub add_error {
    my $self = shift;
    my $msg = shift;

    push @{ $self->{errors}||=[] }, $msg;
}

sub errors {
    my $self = shift;
    return $self->{errors} ? delete $self->{errors} : [];
}

sub is_success {
    my $self = shift;
    return scalar @{ $self->{errors} || [] } ? 0 : 1;
}

1;
