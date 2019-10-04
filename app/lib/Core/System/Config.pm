package Core::System::Config;
use v5.14;

use base qw( Core::System::Service );

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
        open( my $fd, "/etc/environment" ) or die $!;
        while (<$fd>) {
            chomp;
            my ( $tag, $value ) = split(/=/);
            $ENV{ $tag } = $value;
        }
        close $fd;

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

1;


