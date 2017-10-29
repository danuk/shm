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
        params => undef,
    }
}

sub servers_by_group_id {
    my $self = shift;
    my %args = (
        gid => undef,
        @_,
    );

    return $self->_list( where => { server_gid => $args{gid} } );
}

1;
