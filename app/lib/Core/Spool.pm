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
        id => {
            type => 'key',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        user_service_id => {
            type => 'number',
        },
        event => { type => 'json', value => undef },
        prio => {           # приоритет команды
            type => 'number',
            default => 0,
        },
        status => {         # status выполнения команды: 0-новая, 1-выполнена, 2-ошибка
            type => 'number',
            default => TASK_NEW,
        },
        response => { type => 'json', value => undef },
        created => {        # дата создания задачи
            type => 'now',
        },
        executed => {       # дата и время последнего выполнения
            type => 'date',
        },
        delayed => {        # задерка в секундах
            type => 'date',
            default => 0,
        },
        settings => { type => 'json', value => undef },
    }
}

sub push {
    my $self = shift;

    $self->add( @_ );
}

# формирует и выдает список задач для исполнения
# список формируется именно в том порядке, в котором должен выполнятся
sub list_for_all_users {
    my $self = shift;
    my %args = (
        limit => 10,
        @_,
    );
    my @vars;

    return $self->_list(
        where => {
            status => { -not_in => [ TASK_STUCK, TASK_PAUSED ] },
            executed => [
                undef,
                { '<', \[ '? - INTERVAL `delayed` SECOND', now ] },
            ],
        },
        order => [ id => 'asc' ],
        limit => $args{limit},
        extra => 'FOR UPDATE SKIP LOCKED',
    );
}

sub process_all {
    my $self = shift;

    my @list = $self->list_for_all_users( limit => 10 );
    $self->process_one( $_ ) for @list;
}

sub process_one {
    my $self = shift;
    my $task = shift;

    unless ( $task ) {
       ( $task ) = $self->list_for_all_users( limit => 1 );
    }
    return undef unless $task;

    my $user = get_service('user', _id => $task->{user_id} );
    switch_user( $task->{user_id } );
    if ( $user->id != 1 ) {
        return undef unless $user->lock( timeout => 5 );
    }

    my $spool = get_service('spool', _id => $task->{id} )->res( $task );

    unless ( $user ) {
        $spool->finish_task(
            status => TASK_STUCK,
            response => { error => "User $task->{user_id} not exists" },
        );
        return undef;
    }

    if ( my $usi = $task->{settings}->{user_service_id} ) {
        if ( my $service = get_service('us', _id => $usi ) ) {
            return undef unless $service->lock;
        } else {
            $spool->finish_task(
                status => TASK_STUCK,
                response => { error => "User service $usi not exists" },
            );
            return undef;
        }
    }

    if ( $task->{event}->{server_gid} ) {
        my @servers = get_service('ServerGroups', _id => $task->{event}->{server_gid} )->get_servers;
        unless ( @servers ) {
            logger->warning("Can't found servers for group: $task->{event}->{server_gid}");
            $spool->finish_task(
                status => TASK_STUCK,
                response => { error => "Can't found servers for group" },
            );
            return TASK_STUCK, $task, {};
        }

        $task->{settings}->{server_id} = $servers[0]->{server_id};

        if ( scalar @servers > 1 ) {
            # TODO: create new tasks for all servers
        }
    }

    my ( $status, $info ) = $spool->make_task();

    logger->warning('Task fail: ' . Dumper $info ) if $status ne TASK_SUCCESS;

    if ( $status eq TASK_SUCCESS ) {
        $spool->finish_task(
            status => $status,
            %{ $info },
        );
    }
    elsif ( $status eq TASK_FAIL ) {
        $spool->retry_task(
            status => TASK_FAIL,
            %{ $info },
        )
    }
    elsif ( $status eq TASK_STUCK ) {
        $spool->finish_task(
            status => TASK_STUCK,
            %{ $info },
        );
    } else {
        $spool->set( status => $status );
    }

    return $status, $task, $info;
}

sub finish_task {
    my $self = shift;
    my %args = (
        status => TASK_SUCCESS,
        @_,
    );

    $self->set(
        executed => now,
        $self->event->{period} ? (delayed => $self->event->{period} ) : (),
        %args,
    );

    if ( $args{status} ne TASK_SUCCESS ) {
        if ( $self->settings->{user_service_id} ) {
            if ( my $us = get_service('us', _id => $self->settings->{user_service_id} ) ) {
                $us->set( status => STATUS_ERROR );
            }
        }
    } else {
        if ( $self->event->{kind} eq 'Jobs' && $self->event->{period} ) {
            $self->write_history if $args{status} ne TASK_SUCCESS;
        }
        else {
            $self->write_history;
            $self->delete;
        }
    }
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
        delayed => ( ($self->res->{delayed}||=1) * 5 ),
    );

    $self->write_history;
}

sub api_manual_action {
    my $self = shift;
    my %args = (
        id => undef,
        action => undef,
        @_,
    );

    my $method = sprintf( "api_%s", delete $args{action} );
    unless ( $self->can( $method ) ) {
        my $report = get_service('report');
        $report->add_error('unknown action');
        return ();
    }
    return $self->id( $args{ id } )->$method( %args );
}

sub api_success {
    my $self = shift;
    my %args = (
        event => undef,
        settings => undef,
        @_,
    );

    $self->finish_task(
        status => TASK_SUCCESS,
    );

    if ( $args{settings} && $args{settings}->{user_service_id} && $args{event} && $args{event}->{name} ) {
        if ( my $us = get_service('us', _id => $args{settings}->{user_service_id} ) ) {
            $us->set_status_by_event( $args{event}->{name} );
        }
    }

    return scalar $self->get;
}

sub api_retry {
    my $self = shift;
    my %args = (
        event => undef,
        settings => undef,
        @_,
    );

    $self->set(
        event => $args{event},
        settings => $args{settings},
        status => TASK_NEW,
        executed => undef,
        delayed => 0,
    ) if $args{event};

    if ( my $usi = $self->settings->{user_service_id} ) {
        if ( my $us = get_service('us', _id => $usi ) ) {
            $us->set( status => STATUS_PROGRESS );
        }
    }

    return scalar $self->get;
}

sub api_pause {
    my $self = shift;

    $self->set(
        status => TASK_PAUSED,
    );
    return scalar $self->get;
}

sub api_resume {
    my $self = shift;

    $self->set(
        status => TASK_NEW,
        delayed => 0,
    );
    return scalar $self->get;
}

sub write_history {
    my $self = shift;

    get_service('SpoolHistory')->add( $self->get );
}

1;
