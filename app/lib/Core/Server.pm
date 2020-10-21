package Core::Server;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'servers' };

sub structure {
    return {
        server_id => {
            type => 'key',
        },
        server_gid => {
            type => 'number',
        },
        name => {
            type => 'number',
        },
        transport => {         # ssh,http,etc...
            type => 'text',
        },
        host => {
            type => 'text',
        },
        ip => {                # ip адрес для построения DNS
            type => 'text',
        },
        weight => {
            type => 'number',
        },
        success_count => {
            type => 'number',
        },
        fail_count => {
            type => 'number',
        },
        enabled => {
            type => 'number',
        },
        settings => { type => 'json', value => undef },
    }
}

sub servers_by_group_id {
    my $self = shift;
    my %args = (
        gid => undef,
        @_,
    );

    return $self->_list( where => {
        server_gid => $args{gid},
        enabled => 1,
    });
}

sub key_id {
    my $self = shift;

    my $key_id = $self->res->{settings}->{key_id};
    return undef unless $key_id;
}

sub key_file {
    my $self = shift;

    my $key_id = $self->key_id || return undef;

    if ( my $obj = get_service('Identities', _id => $key_id) ) {
        return $obj->private_key_file;
    };
    return undef;
}

sub add {
    my $self = shift;
    my %args = (
        @_,
    );

    $args{transport} ||= $args{server}->{transport};

    return $self->SUPER::add( %args );
}

1;
