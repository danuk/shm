package Core::Report;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;

*error = \&add_error;
*warning = \&add_error;

sub _id {}; # всегда один экземляр для всех

sub add_error {
    my $self = shift;
    my @msg = @_;
    my $msg;
    if (ref $msg[0]) {
        $msg = $msg[0];
    } else {
        $msg = join(' ', @msg);
    }
    logger->warning( $msg );
    push @{ $self->{errors}||=[] }, $msg;
    return $msg;
}

sub status {
    my $self = shift;
    my $status = shift;

    if ( $status ) {
        $self->{status} = $status;
    }

    return $self->{status};
}

sub headers {
    my $self = shift;
    my $headers = shift;

    $self->{headers} ||= {};

    if ( ref $headers eq 'HASH' ) {
        $self->{headers} = $headers;
    }

    if ( my $status = $self->status ) {
        $self->{headers}->{status} = $status;
    }

    return wantarray ? %{ $self->{headers} } : $self->{headers};
}

sub errors {
    my $self = shift;
    my $ret = $self->{errors} ? delete $self->{errors} : [];
    return wantarray ? @{ $ret } : $ret;
}

sub is_success {
    my $self = shift;
    return scalar @{ $self->{errors} || [] } ? 0 : 1;
}

1;
