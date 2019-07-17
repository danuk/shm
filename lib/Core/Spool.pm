package Core::Spool;

use v5.14;
use parent qw/Core::Task Core::Base/;
use Core::Base;
use Core::Const;
use Core::Utils qw( now );
use Core::Task;
use Core::Utils;

sub table { return 'spool' };

sub structure {
    return {
        id => '@',
        user_id => '!',
        event => { type => 'json', value => undef },
        prio => 0,          # приоритет команды
        status => TASK_NEW, # status выполнения команды: 0-новая, 1-выполнена, 2-ошибка
        response => { type => 'json', value => undef },
        created => 'now',   # дата создания задачи
        executed => undef,  # дата и время последнего выполнения
        delayed => 0,       # задерка в секундах
        params => { type => 'json', value => undef },
    }
}

sub push {
    my $self = shift;

    $self->add( @_ );
}

# формитрует и выдает список задач для исполнения
# список формируется именно в том порядке, в котором должен выполнятся
sub list_for_all_users {
    my $self = shift;
    my @vars;

    return $self->_list(
        where => {
            executed => [
                undef,
                { '<', \[ '? - INTERVAL `delayed` SECOND', now ] },
            ],
        },
        order => [ id => 'asc' ],
        limit => 100,
    );
}

# обрабатывает один запрос из списка $self->{spool} (список формируется методом: list_for_all_users)
sub process_one {
    my $self = shift;

    $self->{spool}//= [ $self->list_for_all_users() ];
    my $task = shift @{ $self->{spool}//=[] } or return undef;

    switch_user( $task->{user_id } );

    if ( $task->{event}->{server_gid} ) {
        my @servers = get_service('ServerGroups', _id => $task->{event}->{server_gid} )->get_servers;
        unless ( @servers ) {
            get_service('logger')->warning("Can't found servers for group: $task->{event}->{server_gid}");
            my $spool = get_service('spool', _id => $task->{id} )->res( $task );
            $spool->finish_task(
                status => TASK_DROP,
                error => "Can't found servers for group",
            );
            return TASK_DROP, {};
        }

        $task->{params}->{server_id} = $servers[0]->{server_id};

        if ( scalar @servers > 1 ) {
            # TODO: create new tasks for all servers
        }
    }

    my $spool = get_service('spool', _id => $task->{id} )->res( $task );

    my ( $status, $info ) = $spool->make_task();

    get_service('logger')->warning('Task fail: ' . Dumper $info ) if $status != TASK_SUCCESS;

    if ( $status == TASK_SUCCESS || $status == TASK_DROP ) {
        $spool->finish_task(
            status => $status,
            %{ $info },
        );
    }
    elsif ( $status == TASK_FAIL ) {
        $spool->retry_task(
            status => TASK_FAIL,
            %{ $info },
        );
    }

    #TODO: destroy spool object

    return $status, $info;
}

sub finish_task {
    my $self = shift;
    my %args = (
        status => TASK_SUCCESS,
        @_,
    );

    if ( $args{status} != TASK_SUCCESS ) {
        if ( $self->params->{user_service_id} ) {
            if ( my $us = get_service('us', _id => $self->params->{user_service_id} ) ) {
                $us->set( status => STATUS_ERROR );
            }
        }
    }

    $self->set(
        executed => now,
        %args,
    );

    $self->write_history;
    $self->delete;
}

# TODO: check max retries
sub retry_task {
    my $self = shift;
    my %args = (
        status => undef,
        @_,
    );

    $self->set(
        %args,
        status => $args{status},
        executed => now,
        delayed => ( $self->res->{delayed}||=1 * 5 ),
    );

    $self->write_history;
}

sub write_history {
    my $self = shift;

    get_service('SpoolHistory')->add( $self->get );
}

1;
