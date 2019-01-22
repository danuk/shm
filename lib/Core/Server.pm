package Core::Server;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'servers' };

sub structure {
    return {
        server_id => '@',
        server_gid => undef,
        name => undef,
        transport => '?',       # ssh,http,etc...
        host => undef,
        ip => undef,            # ip адрес для построения DNS
        weight => undef,
        success_count => undef,
        fail_count => undef,
        enabled => 1,
        params => { type => 'json', value => undef },
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

    my $key_id = $self->res->{params}->{key_id};
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

1;
