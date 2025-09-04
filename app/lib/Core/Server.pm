package Core::Server;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'servers' };

sub structure {
    return {
        server_id => {
            type => 'number',
            key => 1,
            title => 'id сервера',
        },
        server_gid => {
            type => 'number',
            title => 'id группы',
        },
        name => {
            type => 'text',
            title => 'имя сервера',
        },
        transport => {         # ssh,http,etc...
            type => 'text',
            enum => ['ssh','http','telegram','mail','local'],
            title => 'транспорт',
        },
        host => {
            type => 'text',
            title => 'адрес сервера',
        },
        ip => {                # ip адрес для построения DNS
            type => 'text',
            title => 'ip сервера',
        },
        weight => {
            type => 'number',
            title => 'вес сервера для выборки',
            description => 'чем больше вес, тем выше вероятность выборки',
        },
        success_count => {
            type => 'number',
            title => 'не используется',
        },
        fail_count => {
            type => 'number',
            title => 'не используется',
        },
        services_count => {
            type => 'number',
            title => 'кол-во услуг на сервере',
        },
        enabled => {
            type => 'number',
            enum => [0,1],
            title => 'флаг включенного сервера',
            description => '0 - выключен, 1 - включен',
        },
        settings => { type => 'json', value => {} },
    }
}

sub servers_by_group_id {
    my $self = shift;
    my @args = @_;

    my $gid;

    if ( scalar @args == 1 ) {
        $gid = $args[0];
    } else {
        $gid = $args[1]; # gid => N
    }

    return $self->_list( where => {
        server_gid => $gid,
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

sub delete {
    my $self = shift;

    my @ret = $self->srv('us')->_list(
        where => {
            'settings.server_id' => $self->id,
            status => { '!=', 'REMOVED' },
        },
        limit => 1,
    );

    if ( @ret ) {
        logger->error("Can't delete server ".$self->id." - it is used by user services");
        return undef;
    }
    return $self->SUPER::delete();
}

1;
