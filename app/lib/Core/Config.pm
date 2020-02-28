package Core::Config;
use v5.14;

use parent 'Core::Base';
use Core::Base;

our $config;
our $session_config;
require 'shm.conf';

sub table { return 'config' };

sub structure {
    return {
        key => '@',
        value => '?',
    }
}

sub table_allow_insert_key { return 1 };

sub validate_attributes {
    my $self = shift;
    my $method = shift;
    my %args = @_;

    my $report = get_service('report');

    unless ( $args{key} || $args{value} ) {
        $report->add_error('KeyOrValueNotPresent');
    }

    if ( $args{key} =~/^_/ ) {
        $report->add_error('KeyProhibited');
    }

    return $report->is_success;
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

    my %ret = map{ $_->{key} => $_->{value} } @list;

    return \%ret;
}

sub clean_protected_keys {
    my %args = @_;

    delete $args{ $_ } for grep( /^_/, keys %args );
    return %args;
}

1;

