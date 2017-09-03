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
        require 'shm.conf';
    }
    return bless(\%args, $class);
}

sub get {
    return {
        config => $config,
        session_config => $session_config,
    };
}

1;


