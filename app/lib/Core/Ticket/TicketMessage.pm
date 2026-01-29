package Core::Ticket::TicketMessage;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;

sub table { return 'ticket_messages' };

sub structure {
    return {
        message_id => {
            type => 'number',
            key => 1,
            title => 'ID сообщения',
        },
        ticket_id => {
            type => 'number',
            required => 1,
            title => 'ID тикета',
        },
        user_id => {
            type => 'number',
            title => 'ID пользователя',
        },
        admin_id => {
            type => 'number',
            title => 'ID администратора',
        },
        is_admin => {
            type => 'number',
            default => 0,
            title => 'От администратора',
        },
        message => {
            type => 'text',
            required => 1,
            title => 'Текст сообщения',
        },
        media => {
            type => 'json',
            title => 'Прикрепленные файлы',
        },
        created => {
            type => 'date',
            title => 'Дата создания',
            readOnly => 1,
        },
    }
}

1;
