package Core::Spool;

use v5.14;
use parent qw/Core::Task Core::Base/;
use Core::Base;
use Core::Const;
use Core::Utils qw( now );
use Core::Task;
use Core::Utils;
use Time::HiRes qw(time);

sub table { return 'spool' };

sub structure {
    return {
        id => {
            type => 'number',
            key => 1,
            title => 'id задачи',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
            title => 'id пользователя',
        },
        user_service_id => {
            type => 'number',
            title => 'id услуги пользователя',
        },
        event => {
            type => 'json',
            value => {},
            title => 'событие в формате JSON',
        },
        prio => {           # приоритет команды
            type => 'number',
            default => 100,
            title => 'приоритет команды',
            description => 'чем выше приоритет, тем раньше выполнится задача',
        },
        status => {         # status выполнения команды: 0-новая, 1-выполнена, 2-ошибка
            type => 'text',
            default => TASK_NEW,
            enum => [TASK_NEW,TASK_SUCCESS,TASK_FAIL,TASK_DELAYED,TASK_STUCK,TASK_PAUSED],
            title => 'статус задачи',
        },
        response => {
            type => 'json',
            value => {},
            title => 'результат выполнения задачи',
            readOnly => 1,
        },
        created => {        # дата создания задачи
            type => 'now',
            title => 'дата создания задачи',
            readOnly => 1,
        },
        executed => {       # дата и время последнего выполнения
            type => 'date',
            title => 'дата выполнения задачи',
            readOnly => 1,
        },
        delayed => {        # задерка в секундах
            type => 'date',
            default => 0,
            title => 'время задержки выполнения в секундах',
        },
        settings => { type => 'json', value => {} },
    }
}

sub push {
    my $self = shift;

    $self->add( @_ );
}

sub api_add {
    my $self = shift;
    my %args = (
        prio => 100,
        @_,
    );
    return $self->SUPER::api_add( %args );
}

sub add {
    my $self = shift;
    my %args = (
        get_smart_args( @_ ),
    );

    if ( $args{status} eq TASK_NEW && $args{delayed} && $args{delayed} > 0  ) {
        $args{status} = TASK_DELAYED;
        $args{executed} = now; # delay вычисляется от текущего времени
    } elsif ( $args{status} eq TASK_SUCCESS && $args{event} && $args{event}{period} && $args{event}{period} > 0 ) {
        $args{status} = TASK_DELAYED;
    }

    if ( my $task_id = $self->{task_id} ) {
        $args{event}{task_id} ||= $task_id;
    }

    return $self->SUPER::add( %args );
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
        order => [
            prio => 'asc',
            id => 'asc',
        ],
        limit => $args{limit},
        extra => 'FOR UPDATE SKIP LOCKED',
    );
}

sub process_all { # for unit tests
    my $self = shift;

    my @list = $self->list_for_all_users( limit => 10 );
    $self->process_one( $_ ) for @list;
}

sub process_one { # for spool.pl
    my $self = shift;
    my $task = shift;

    unless ( $task ) {
       ( $task ) = $self->list_for_all_users( limit => 1 );
    }
    return undef unless $task;

    my $spool = get_service('spool', _id => $task->{id} )->res( $task );
    # Запись факта запуска задачи в историю ДО выполнения
    $spool->write_history_start;

    my $user = get_service('user', _id => $task->{user_id} );
    unless ( $user ) {
        $spool->finish_task(
            status => TASK_STUCK,
            response => { error => "User $task->{user_id} not exists" },
        );
        return $spool;
    }
    switch_user( $task->{user_id } );

    if ( my $usi = $task->{settings}->{user_service_id} ) {
        if ( my $us = get_service('us', _id => $usi ) ) {
            unless ( $us->lock ) {
                $spool->retry_task(
                    status => TASK_DELAYED,
                    response => { error => "User service is locked" },
                );
                return $spool;
            }
        } else {
            $spool->finish_task(
                status => TASK_SUCCESS,
                response => { error => "User service is not exists" },
            );
            return $spool;
        }
    }

    if ( $task->{event}->{server_gid} ) {
        my $server_group = get_service('ServerGroups', _id => $task->{event}->{server_gid} );
        unless ( $server_group ) {
            logger->warning("The server group does not exist: $task->{event}->{server_gid}");
            $spool->finish_task(
                status => TASK_STUCK,
                response => { error => "The server group does not exist" },
            );
            return $spool, {};
        }

        my @servers = $server_group->get_servers;
        unless ( @servers ) {
            logger->warning("Can't found servers for group: $task->{event}->{server_gid}");
            $spool->finish_task(
                status => TASK_STUCK,
                response => { error => "Can't found servers for group" },
            );
            return $spool, {};
        }

        $task->{settings}->{server_id} = $servers[0]->{server_id};

        if ( scalar @servers > 1 ) {
            # TODO: create new tasks for all servers
        }
    }

    if ( my $server_id = $task->{settings}->{server_id} ) {
        my $server = get_service('server', _id => $server_id );
        unless ( $server ) {
            $spool->finish_task(
                status => TASK_STUCK,
                response => { error => sprintf( "Server not exists: %d", $server_id ) },
            );
            return $spool, {};
        }
    }

    my ( $status, $info ) = $spool->make_task();

    logger->warning('Task fail: ' . Dumper $info ) if $status ne TASK_SUCCESS;

    if ( $status eq TASK_SUCCESS || $status eq 'MOCK' ) {
        $spool->finish_task(
            status => $status,
            %{ $info },
        );
    }
    elsif ( $status eq TASK_FAIL || $status eq TASK_DELAYED ) {
        $spool->retry_task(
            status => $status,
            %{ $info },
        )
    }
    else { # TASK_STUCK
        $spool->finish_task(
            status => TASK_STUCK,
            %{ $info },
        );
    }

    return $spool, $info;
}

sub finish_task {
    my $self = shift;
    my %args = (
        status => TASK_SUCCESS,
        @_,
    );

    $self->set(
        executed => now,
        %args,
    );

    $self->write_history;

    if ( $args{status} eq TASK_SUCCESS ) {
        if ( $self->is_periodic ) {
            $self->set(
                delayed => $self->event->{period},
                status => TASK_DELAYED,
            )
        } else {
            $self->delete;
        }
    }
}

sub is_periodic {
    my $self = shift;
    return $self->event && $self->event->{period} && $self->event->{period} > 0;
}

# TODO: check max retries
sub retry_task {
    my $self = shift;
    my %args = (
        status => undef,
        @_,
    );

    my $delayed = $self->res->{delayed}||=1;
    $delayed ||= 1;  # ensure numeric value
    # не меняем делей, если задан вручную (больше 15 мин)
    if ( $delayed < 900 ) {
        $delayed *= 3;  # 3s, 9s, 27s, 81s,...
        $delayed = 900 if $delayed > 900; # max 15 min
    } else {
        # set minimal delay for retry tasks with custom delay
        $delayed = 3;
    }

    $self->set(
        %args,
        status => $args{status},
        executed => now,
        delayed => $delayed,
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

sub api_pause {
    my $self = shift;

    $self->set(
        status => TASK_PAUSED,
    );
    return scalar $self->get;
}

*api_resume = \&api_retry;

sub api_retry {
    my $self = shift;

    $self->set(
        status => TASK_NEW,
        delayed => 0,
    );
    return scalar $self->get;
}

sub history {
    my $self = shift;
    state $history ||= $self->srv('SpoolHistory');
    return $history;
}

sub write_history_start {
    my $self = shift;
    my %task_data = $self->get;

    $self->{spool} = {
        pid => $$,
        started => time(),
    };
    $task_data{response}{spool} = $self->{spool};

    my $history_id = $self->history->add(
        %task_data,
        created => now,
    );

    $self->{history_id} = $history_id;
}

sub write_history {
    my $self = shift;
    my %task_data = $self->get;

    if ( $self->{spool}{started} ) {
        my $time = time();
        $self->{spool}{finished} = $time;
        $self->{spool}{duration} = sprintf( "%.5f", $time - $self->{spool}{started} ) + 0;
        $task_data{response}{spool} = $self->{spool};
    }

    if ( my $history = $self->history->id( $self->{history_id} ) ) {
        # Обновляем существующую запись
        $history->set( %task_data );
    } else {
        # Старое поведение — если по каким-то причинам history_id нет
        $self->history->add( %task_data );
    }
}

1;
