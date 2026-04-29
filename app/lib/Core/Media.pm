package Core::Media;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use MIME::Base64 qw(decode_base64);

sub table { return 'media' }

sub structure {
    return {
        id => {
            type => 'number',
            key => 1,
            title => 'ID',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
            title => 'ID пользователя',
        },
        entity_type => {
            type => 'text',
            title => 'Тип объекта',
        },
        entity_id => {
            type => 'number',
            title => 'ID объекта',
        },
        name => {
            type => 'text',
            required => 1,
            title => 'Имя файла',
        },
        mime_type => {
            type => 'text',
            title => 'MIME тип',
        },
        size => {
            type => 'number',
            title => 'Размер (байт)',
        },
        data => {
            type => 'blob',
            title => 'Данные',
            protected => 1,
        },
        created => {
            type => 'date',
            title => 'Дата загрузки',
            readOnly => 1,
        },
    }
}

sub link_to_entity {
    my $self = shift;
    my %args = @_;

    $self->set(
        entity_type => $args{entity_type},
        entity_id   => $args{entity_id},
    );

    return $self;
}

sub api_upload {
    my $self = shift;
    my %args = @_;

    unless ( $args{name} && $args{data} ) {
        report->add_error('Необходимы поля name и data');
        return undef;
    }

    my $raw = eval { decode_base64( $args{data} ) };
    if ( $@ || !defined $raw ) {
        report->add_error('Некорректный base64');
        return undef;
    }

    my $size = length($raw);
    if ( $size > 10 * 1024 * 1024 ) {
        report->add_error('Файл слишком большой (максимум 10 МБ)');
        return undef;
    }

    my $id = $self->add(
        name      => $args{name},
        mime_type => $args{mime_type} || 'application/octet-stream',
        size      => $size,
        data      => $raw,
    );

    return $id ? scalar $self->id($id)->get : undef;
}

# Скачать файл. Возвращает сырые байты (format => media в роуте).
sub api_data {
    my $self = shift;
    my %args = @_;

    my $media = $self->id( $args{id} );
    return undef unless $media;

    my $row = $media->res;

    my $allowed = $args{admin} || $row->{user_id} == $self->user_id;

    unless ( $allowed ) {
        # Разрешаем доступ если медиа привязана к сообщению тикета пользователя
        if ( $row->{entity_type} && $row->{entity_type} eq 'ticket_message' && $row->{entity_id} ) {
            my $msg = get_service('Tickets::TicketMessages')->id( $row->{entity_id} );
            if ( $msg && $msg->res->{ticket_id} ) {
                my $ticket = get_service('Ticket')->id( $msg->res->{ticket_id} );
                $allowed = 1 if $ticket && $ticket->res->{user_id} == $self->user_id;
            }
        }
    }

    unless ( $allowed ) {
        report->add_error('Доступ запрещён');
        return undef;
    }

    return $row->{data};
}

1;
