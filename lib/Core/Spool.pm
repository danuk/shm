package Core::Spool;

use v5.14;
use parent qw/Core::Task Core::Base/;
use Core::Base;
use Core::Utils qw( now );
use Core::Task;

sub id {
    my $self = shift;
    return $self->{id};
}

sub table { return 'spool' };

sub structure {
    return {
        id => '@',

        user_id => '!',
        user_service_id => undef, # идентификатор услуги

        category => '?',    # web,mail,mysql,etc...
        event => '?',       # create,prolongate,block,unblock,etc...

        server_gid => undef,
        server_id => undef,
        data => undef,      # любые дополнительные данные
        prio => 0,          # приоритет команды

        status => TASK_NEW, # status выполнения команды: 0-новая, 1-выполнена, 2-ошибка
        responce => undef,

        created => 'now',   # дата создания задачи
        executed => undef,  # дата и время последнего выполнения
        delayed => 0,       # задерка в секундах
    }
}

sub push {
    my $self = shift;

    $self->add( @_ );
}

sub list {
    my $self = shift;
    return $self->SUPER::list( order => [ prio => 'desc', id => 'asc' ] );
}

# формитрует и выдает список задач для исполнения
# список формируется именно в том порядке, в котором должен выполнятся
sub list_for_all_users {
    my $self = shift;
    my @vars;

    my $query = $self->query_select(
        vars => \@vars,
        where => {
            executed => [
                undef,
                { '<', \[ '? - INTERVAL `delayed` SECOND', now ] },
            ],
        },
        order => [ user_id => 'asc', server_id => 'asc', prio => 'desc' ],
        limit => 100,
    );
    return $self->{spool} = $self->query( $query, @vars );
}

# обрабатывает один запрос из списка $self->{spool} (список формируется методом: list_for_all_users)
sub process_one {
    my $self = shift;

    $self->{spool}//= $self->list_for_all_users();
    my $task = shift @{ $self->{spool}//=[] } or return undef;

    if ( $task->{server_gid} ) {
        my @servers = get_service('ServerGroups', _id => $task->{server_gid} )->get_servers;
        unless ( @servers ) {
            get_service('logger')->warning("Can't found servers for group: $task->{server_gid}");
            my $spool = get_service('spool', _id => $task->{id} )->res( $task );
            $spool->finish_task(
                status => TASK_DROP,
                error => "Can't found servers for group",
            );
            return TASK_DROP, {};
        }

        $task->{server_id} = $servers[0]->{server_id};

        if ( scalar @servers > 1 ) {
            # TODO: create new tasks for all servers
        }
    }

    my $spool = get_service('spool', _id => $task->{id} )->res( $task );

    my ( $status, $info ) = $spool->make_task();

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
        status => undef,
        @_,
    );

    $self->set(
        executed => now,
        %args,
    );

    $self->write_history;
    # TODO: $self->delete;
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
