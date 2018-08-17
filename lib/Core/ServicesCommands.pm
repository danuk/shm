package Core::ServicesCommands;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'services_commands' };

sub structure {
    return {
        id => '@',
        name => '?',
        category => '?',    # www,mail,mysql
        event => '?',       # create,block,unblock...
        server_gid => '?',  # Group_id of servers
        params => '?',
    }
}

sub get_events {
    my $self = shift;
    my $args = {
        category => undef,
        event => undef,
        @_,
    };

    my @res = $self->list(
        where => {
            category => $args->{category},
            event => $args->{event},
        },
    );
    return wantarray ? @res : \@res;
}

sub data {
    my $self = shift;

    unless ( $self->id && $self->{res} ) {
        get_service('logger')->error("Data not loaded");
    }
    return wantarray ? @{ $self->{res} } : $self->{res};
}

sub command {
    my $self = shift;
    return $self->data->{command};
}

sub exec {
    my $self = shift;
    my $args = {
        server_id => undef,
        data => undef,
        @_,
    };

    return get_service('spool')->push(
        server_id => $args->{server_id},
        cmd => $self->command,
        data => $args->{data},
    );
}

1;
