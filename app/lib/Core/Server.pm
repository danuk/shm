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
        services_count => {
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

sub list_by_transport {
    my $self = shift;
    my $transport = shift;

    return () unless $transport;

    my @servers = $self->_list(
        where => {
            transport => $transport,
            enabled => 1,
        },
    );

    return @servers;
}

sub services_count_increase {
    my $self = shift;

    my $ret = $self->do("UPDATE servers SET services_count=services_count+1 WHERE server_id=?", $self->id );
    $self->reload() if $ret;
}

sub services_count_decrease {
    my $self = shift;

    my $ret = $self->do("UPDATE servers SET services_count=services_count-1 WHERE server_id=?", $self->id );
    $self->reload() if $ret;
}

sub groups {
    my $self = shift;
    return get_service('ServerGroups');
}

sub group {
    my $self = shift;

    if ( my $group = get_service('ServerGroups', _id => $self->get_server_gid ) ) {
        return $group;
    }
    return undef;
}

1;
