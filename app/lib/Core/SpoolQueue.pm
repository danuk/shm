package Core::SpoolQueue;

use v5.14;
use parent qw/Core::Base/;
use Core::Base;
use Core::Const;

sub table { return 'spool_queues' }
sub dbh { shift->dbh_auto_commit };

my %STATUS_COLUMN = (
    TASK_SUCCESS() => 'cnt_success',
    TASK_FAIL()    => 'cnt_fail',
    TASK_DELAYED() => 'cnt_delayed',
    TASK_STUCK()   => 'cnt_stuck',
    TASK_PAUSED()  => 'cnt_paused',
    TASK_SKIPPED() => 'cnt_skipped',
);

sub structure {
    return {
        id => {
            type  => 'number',
            key   => 1,
            title => 'id очереди',
        },
        name => {
            type     => 'text',
            required => 1,
            title    => 'название очереди',
        },
        rate_limit => {
            type        => 'number',
            title       => 'максимальное количество задач в секунду',
            description => 'NULL — без ограничений',
        },
        status => {
            type    => 'text',
            default => 'active',
            enum    => [ 'active', 'paused' ],
            title   => 'статус очереди',
        },
        last_executed_at => {
            type     => 'date',
            title    => 'время последнего выполнения задачи из очереди',
            readOnly => 1,
        },
        created_at => {
            type     => 'now',
            title    => 'дата создания очереди',
            readOnly => 1,
        },
        finished_at => {
            type     => 'date',
            title    => 'дата завершения очереди',
            readOnly => 1,
        },
        total_added  => { type => 'number', default => 0, title => 'всего добавлено задач',    readOnly => 1 },
        cnt_success  => { type => 'number', default => 0, title => 'выполнено успешно',        readOnly => 1 },
        cnt_fail     => { type => 'number', default => 0, title => 'завершено с ошибкой',      readOnly => 1 },
        cnt_delayed  => { type => 'number', default => 0, title => 'отложено',                 readOnly => 1 },
        cnt_stuck    => { type => 'number', default => 0, title => 'зависло',                  readOnly => 1 },
        cnt_paused   => { type => 'number', default => 0, title => 'поставлено на паузу',      readOnly => 1 },
        cnt_skipped  => { type => 'number', default => 0, title => 'пропущено',                readOnly => 1 },
        cnt_pending  => { type => 'number', default => 0, title => 'ожидают выполнения',       readOnly => 1 },
    }
}

# Возвращает процент выполненных задач (0..100) или undef если задач не было.
# Учитывает SUCCESS и SKIPPED как завершённые.
sub progress {
    my $self = shift;
    my %data = $self->get;
    return undef unless $data{total_added} && $data{total_added} > 0;
    my $done = ( $data{cnt_success} || 0 ) + ( $data{cnt_skipped} || 0 );
    return int( $done / $data{total_added} * 100 + 0.5 );
}

# Вызывается после каждого изменения статуса задачи из этой очереди.
# Инкрементит соответствующий счётчик и обновляет last_executed_at.
# is_terminal => 1 означает, что задача окончательно покинула очередь:
#   декрементит cnt_pending и ставит finished_at когда cnt_pending достигает нуля.
sub on_task_finish {
    my $self = shift;
    my ( $status, %opts ) = @_;

    my $col = $STATUS_COLUMN{ $status } or return $self;

    my $set = "last_executed_at = NOW(), $col = $col + 1";
    $set .= ', cnt_pending = GREATEST(cnt_pending - 1, 0)' if $opts{is_terminal};

    $self->dbh->do(
        "UPDATE spool_queues SET $set WHERE id = ?",
        undef, $self->id
    );

    # Ставим finished_at отдельным запросом: проверяем реальное значение cnt_pending
    # после декремента, а не предсказанное. Это исключает ложное срабатывание.
    # cnt_stuck = 0 — очередь не считается завершённой если есть зависшие задачи.
    if ( $opts{is_terminal} ) {
        $self->dbh->do(
            "UPDATE spool_queues SET finished_at = COALESCE(finished_at, NOW())"
            . " WHERE id = ? AND cnt_pending = 0 AND cnt_stuck = 0 AND total_added > 0 AND finished_at IS NULL",
            undef, $self->id
        );
    }

    return $self;
}

sub inc_added {
    my $self = shift;
    $self->dbh->do(
        'UPDATE spool_queues SET total_added = total_added + 1, cnt_pending = cnt_pending + 1, finished_at = NULL WHERE id = ?',
        undef, $self->id
    );
    return $self;
}

sub api_pause {
    my $self = shift;
    $self->set( status => 'paused' );
    return scalar $self->get;
}

sub api_resume {
    my $self = shift;
    $self->set( status => 'active' );
    return scalar $self->get;
}

# Находит очередь по имени или создаёт её, возвращает объект с установленным id
sub find_or_create {
    my $self = shift;
    my %args = @_;

    my $name = $args{name} or die 'name required';

    my ( $existing ) = $self->_list(
        where => { name => $name },
        limit => 1,
    );

    if ( $existing ) {
        return $self->id( $existing->{id} );
    }

    my $id = $self->add(
        name       => $name,
        rate_limit => $args{rate_limit},
        status     => 'active',
    );

    return $self->id( $id );
}

# Удаляет очередь и архивирует все её задачи со статусом DELETED
sub api_delete_cascade {
    my $self = shift;

    my $id = $self->id;

    # Архивируем задачи очереди в spool_history со статусом DELETED
    $self->dbh->do(
        "INSERT INTO spool_history"
        . " (spool_id, user_id, user_service_id, response, event, prio, status, created, executed, `delayed`, settings, queue_id)"
        . " SELECT id, user_id, user_service_id, response, event, prio, 'DELETED', created, NOW(), `delayed`, settings, queue_id"
        . " FROM spool WHERE queue_id = ?",
        undef, $id
    );

    # Удаляем задачи из активного spool
    $self->dbh->do( "DELETE FROM spool WHERE queue_id = ?", undef, $id );

    # Удаляем саму очередь
    $self->dbh->do( "DELETE FROM spool_queues WHERE id = ?", undef, $id );

    return { deleted => 1 };
}

sub cleanup {
    my $self = shift;
    my $days = cfg('billing')->{cleanup}->{ 'SpoolHistory' } // 30;
    return $self unless $days;

    $self->_delete( where => {
        finished_at => { '<', \[ 'NOW() - INTERVAL ? DAY', $days ] },
    });

    return $self;
}

1;
