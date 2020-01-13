package Core::Config;
use v5.14;

use parent 'Core::Base';

our $config;
our $session_config;
require 'shm.conf';

sub table { return 'config' };

sub structure {
    return {
        id => '@',
        name => '?',
        data => '?',
    }
}

sub file {
    my $self = shift;

    return {
        config => $config,
        session => $session_config,
    };
}

sub local {
    my $self = shift;
    my $section = shift;
    my $new_data = shift;

    if ( $new_data ) {
        $self->{config}->{local}->{ $section } = $new_data;
    }

    return $self->{config}->{local} unless $section;
    return $self->{config}->{local}->{ $section };
}

sub data_by_name {
    my $self = shift;

    my @list = $self->list;

    my %ret = map{ $_->{name} => $_->{data} } @list;

    return \%ret;
}

1;

