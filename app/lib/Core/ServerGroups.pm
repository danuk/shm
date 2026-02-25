package Core::ServerGroups;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub table { return 'servers_groups' };

sub structure {
    return {
        group_id => {
            type => 'number',
            key => 1,
            title => 'id группы'
        },
        name => {
            type => 'text',
            title => 'произвольное название группы',
        },
        type => {
            type => 'text',
            default => 'random',
            enum => ['random','by-one','evenly'],
            title => 'способ выборки сервера',
        },
        transport => {
            type => 'text',
            default => 'ssh',
            enum => ['ssh','http','telegram','mail','local'],
            title => 'транспорт',
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

sub delete {
    my $self = shift;
    my %args = (
        group_id => undef,
        @_,
    );

    if ( any { $args{group_id} == $_ } (GROUP_ID_MAIL, GROUP_ID_LOCAL) ) {
        return undef;
    }

    return $self->SUPER::delete( @_ );
}

1;
