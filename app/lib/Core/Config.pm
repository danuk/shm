package Core::Config;
use v5.14;

use parent 'Core::Base';

our $config;
our $session_config;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my %args = (
        id => 'config',
        config => undef,
    );

    $config||= $args{config};

    unless ( $config ) {
        require 'shm.conf';
    }
    my $self = bless(\%args, $class);
    $self->{config} = {
        global => $config,
        session => $session_config,
    };
    return $self;
}

sub get {
    my $self = shift;
    my $section = shift;

    my $config = $self->{config};
    return $config unless $section;

    return wantarray ? %{ $config->{ $section }||={} } : $config->{ $section };
}

sub global {
    my $self = shift;
    return $self->get('global');
}

sub local {
    my $self = shift;
    my $section = shift;
    my $new_data = shift;

    if ( $new_data ) {
        $self->{config}->{local}->{ $section } = $new_data;
    }

    return $self->get('local') unless $section;
    return $self->get('local')->{ $section };
}

sub set {
    my $self = shift;
    my $params = shift;

    $self->{config}->{local} = $params;
}

1;


