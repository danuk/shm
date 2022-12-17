package Core::ServerGroups;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'servers_groups' };

sub structure {
    return {
        group_id => {
            type => 'key',
        },
        name => {
            type => 'text',
        },
        type => {          # способ выборки серверов из группы
            type => 'text',
            default => 'random',
        },
        transport => {
            type => 'text',
            default => 'ssh',
        },
        settings => {
            type => 'text',
        },
    }
}

# Возвращаем сервер (сервера), в зависимости от настоек группы
sub get_servers {
    my $self = shift;

    my $group = $self->get();
    unless ( $group ) {
        logger->error('ServerGroup not found for id: ' . $self->id );
        return undef;
    }

    my @servers = get_service('server')->servers_by_group_id( gid => $self->id );

    if ( $group->{type} eq 'random' ) {
        my $num_server = int rand scalar @servers;
        return ( $servers[ $num_server ] );
    } else {
        logger->error('Unknown type: ' . $group->{type} );
    }

    return undef;
}

1;
