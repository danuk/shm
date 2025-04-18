package Core::ServerGroups;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'servers_groups' };

sub structure {
    return {
        group_id => {
            type => 'number',
            key => 1,
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

    my @list = get_service('server')->servers_by_group_id( gid => $self->id );
    my @servers;

    for ( @list ) {
        if ( $_->{settings}->{max_services} ) {
            if ( $_->{services_count} >= $_->{settings}->{max_services} ) {
                logger->warning('The server', $_->{server_id}, 'is full' );
                next;
            }
        }
        push @servers, $_;
    }

    unless ( scalar @servers ) {
        logger->warning('No servers found in the group');
        return undef;
    }

    if ( $group->{type} eq 'random' ) {
        my $num_server = int rand scalar @servers;
        return ( $servers[ $num_server ] );
    } elsif ( $group->{type} eq 'by-one' ) {
        my @srv = sort { $a->{services_count} <=> $b->{services_count} } @servers;
        return pop @srv;
    } elsif ( $group->{type} eq 'evenly' ) {
        my @srv = sort { $b->{services_count} <=> $a->{services_count} } @servers;
        return pop @srv;
    } else {
        logger->error('Unknown type: ' . $group->{type} );
        return undef;
    }

    return undef;
}

1;
