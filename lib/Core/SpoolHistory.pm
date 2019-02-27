package Core::SpoolHistory;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'spool_history' };

sub structure {
    return {
        id => '@',
        spool_id => '?',

        user_id => '!',
        user_service_id => undef, # идентификатор услуги

        event_id => '?',

        server_gid => undef,
        server_id => undef, # Пишем server_id для возможности параллельного выполнения
        data => undef,      # любые дополнительные данные
        response => { type => 'json', value => undef },  # ответ
        prio => 0,          # приоритет команды

        status => 0,        # status выполнения команды: 0-новая, 1-выполнена, 2-ошибка

        created => undef,   # дата создания задачи
        executed => undef,  # дата и время последнего выполнения
        delayed => 0,       # задерка в секундах
    }
}

sub add {
    my $self = shift;
    my %args = ( @_ );

    $args{ spool_id } = delete $args{id};
    $self->SUPER::add( %args );
}

1;
