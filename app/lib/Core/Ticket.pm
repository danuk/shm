package Core::Ticket;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw(now);

sub table { return 'tickets' };

sub structure {
    return {
        ticket_id => {
            type => 'number',
            key => 1,
            title => 'ID тикета',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
            title => 'ID пользователя',
        },
        subject => {
            type => 'text',
            required => 1,
            title => 'Тема тикета',
        },
        status => {
            type => 'text',
            default => TICKET_OPEN,
            enum => [
                TICKET_OPEN,
                TICKET_IN_PROGRESS,
                TICKET_WAITING,
                TICKET_CLOSED,
                TICKET_ARCHIVED,
            ],
            title => 'Статус',
        },
        priority => {
            type => 'text',
            default => TICKET_NORMAL,
            enum => [
                TICKET_LOW,
                TICKET_NORMAL,
                TICKET_HIGH,
                TICKET_URGENT,
            ],
            title => 'Приоритет',
        },
        ticket_type => {
            type => 'text',
            default => TICKET_OTHER,
            enum => [
                TICKET_SERVICE,
                TICKET_PAYMENT,
                TICKET_OTHER,
            ],
            title => 'Тип тикета',
        },
        user_service_id => {
            type => 'number',
            title => 'ID услуги пользователя',
        },
        created => {
            type => 'date',
            title => 'Дата создания',
            readOnly => 1,
        },
        updated => {
            type => 'date',
            title => 'Дата обновления',
            readOnly => 1,
        },
        closed_at => {
            type => 'date',
            title => 'Дата закрытия',
        },
        archived_at => {
            type => 'date',
            title => 'Дата архивации',
        },
    }
}

sub events {
    return {
        'changed_ticket' => {
            event => {
                title => 'Ticket changed',
                kind => 'Ticket',
            },
        },
    };
}

sub create {
    my $self = shift;
    my %args = (
        subject => 'Новое обращение',
        message => undef,
        message_is_admin => 0,
        @_,
    );

    my $ticket_id = $self->add(
        subject => $args{subject},
        priority => $args{priority} || TICKET_NORMAL,
        ticket_type => $args{ticket_type} || TICKET_OTHER,
        $args{user_service_id} ? (user_service_id => $args{user_service_id}) : (),
        $args{user_id} ? (user_id => $args{user_id}) : (),
    );
    return undef unless $ticket_id;

    my $ticket = $self->id( $ticket_id );
    return undef unless $ticket;

    if ( $args{message} ) {
        $ticket->add_message(
            message => $args{message},
            $args{message_is_admin} ? (is_admin => 1) : (),
            skip_event => 1,
        );
    }

    $self->make_event( 'changed_ticket', settings => { action => 'create', user => 1, message => $args{message} } );

    return $ticket;
}

sub add_message {
    my $self = shift;
    my %args = (
        message => undef,
        media_ids => undef,
        is_admin => 0,
        skip_event => 0,
        @_,
    );

    return undef unless $args{message};

    my $messages = get_service('Tickets::TicketMessages');
    my $msg_id = $messages->add(
        ticket_id => $self->id,
        user_id   => $self->user_id,
        message => $args{message},
        $args{is_admin} ? (is_admin => 1) : (),
    );

    return undef unless $msg_id;

    if ( $args{media_ids} && ref $args{media_ids} eq 'ARRAY' ) {
        my $media_svc = get_service('Media');
        for my $media_id ( @{ $args{media_ids} } ) {
            my $media = $media_svc->id( $media_id );
            next unless $media && !$media->res->{entity_id};
            next if !$args{is_admin} && $media->res->{user_id} != $self->user_id;
            $media->link_to_entity(
                entity_type => 'ticket_message',
                entity_id   => $msg_id,
            );
        }
    }

    $self->set( updated => now() );

    if ( !$args{is_admin} && $self->status eq TICKET_WAITING ) {
        $self->set( status => TICKET_OPEN );
    }

    unless ( $args{skip_event} ) {
        $self->make_event( 'changed_ticket', settings => { action => 'message', ($args{is_admin} ? (initiator => 'admin') : (initiator => 'user')), message => $args{message} } );
    }

    return scalar $messages->id($msg_id)->get;
}

sub messages {
    my $self = shift;

    my $messages = get_service('Tickets::TicketMessages');
    my @msgs = $messages->list(
        where => { ticket_id => $self->id },
        order => [ created => 'ASC' ],
    );

    my $media_svc = get_service('Media');
    for my $msg ( @msgs ) {
        my @media = map { my %m = %$_; delete $m{data}; \%m }
            $media_svc->_list(
                where => {
                    entity_type => 'ticket_message',
                    entity_id   => $msg->{message_id},
                },
            );
        $msg->{media} = \@media;
    }

    return @msgs;
}

sub full_info {
    my $self = shift;

    my $ticket = $self->get;
    return undef unless $ticket;

    my @messages = $self->messages;

    return {
        %{ $self->res },
        messages => \@messages,
    };
}

# User API
sub api_create {
    my $self = shift;
    my %args = @_;

    if ( $args{user_service_id} ) {
        my $us = get_service('us', _id => $args{user_service_id} );
        if ( !$us || $us->res->{user_id} != $self->user_id ) {
            return { error => 'Invalid user_service_id' };
        }
    }

    my $ticket = $self->create(
        subject => $args{subject} || 'Новое обращение',
        message => $args{message},
        priority => $args{priority},
        ticket_type => $args{ticket_type} || TICKET_OTHER,
        user_service_id => $args{user_service_id},
        user_id => $self->user_id,
    );

    return $ticket ? $ticket->get : undef;
}

sub api_list {
    my $self = shift;
    my %args = @_;

    my %where = ( user_id => $self->user_id );
    $where{status} = $args{status} if $args{status};

    my @result;
    for ( $self->list(
        where => \%where,
        order => [ created => 'DESC' ],
        limit => $args{limit},
        offset => $args{offset},
    ) ) {
        my $ticket = $self->id( $_->{ticket_id} );
        push @result, {
            %{ $ticket->res },
            messages => [ $ticket->messages ],
        };
    }

    return @result;
}

sub api_get {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->id( $args{ticket_id} );
    return unless $ticket;

    return undef unless $ticket->res->{user_id} == $self->user_id;

    return $ticket->full_info;
}

sub api_message {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->id( $args{ticket_id} );
    return unless $ticket;

    return undef unless $ticket->res->{user_id} == $self->user_id;

    if ( $ticket->status eq TICKET_CLOSED || $ticket->status eq TICKET_ARCHIVED ) {
        report->add_error('Тикет закрыт');
        return undef;
    }

    return $ticket->add_message(
        message => $args{message},
        media_ids => $args{media_ids},
    );
}

sub api_close {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->id( $args{ticket_id} );
    return unless $ticket;

    return undef unless $ticket->res->{user_id} == $self->user_id;

    return { $ticket->close->get };
}

# Admin API
sub api_admin_create {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->create(
        user_id => $args{user_id},
        subject => $args{subject},
        message => $args{message},
        message_is_admin => 1,
        priority => $args{priority} || TICKET_NORMAL,
    );

    return { error => "Can't create ticket" } unless $ticket;

    return $ticket->full_info;
}

sub api_admin_list {
    my $self = shift;
    my %args = @_;

    my %where;
    $where{status} = $args{status} if $args{status};
    $where{user_id} = $args{user_id} if $args{user_id};
    $where{priority} = $args{priority} if $args{priority};

    return $self->_list(
        where => \%where,
        order => [
            priority => 'desc',
            created => 'desc',
        ],
        limit => $args{limit},
        offset => $args{offset},
        calc => 1,
    );
}

sub api_admin_get {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->id( $args{ticket_id} );
    return unless $ticket;

    return $ticket->full_info;
}

sub api_admin_update {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->id( $args{ticket_id} );
    return unless $ticket;

    my %update;
    $update{status} = $args{status} if $args{status};
    $update{priority} = $args{priority} if $args{priority};

    if ( $args{status} && $args{status} eq TICKET_CLOSED ) {
        $update{closed_at} = now();
    } elsif ( $args{status} && $args{status} eq TICKET_ARCHIVED ) {
        $update{archived_at} = now();
    }

    $ticket->set( %update ) if %update;

    if ( $args{message} ) {
        $ticket->add_message(
            message => $args{message},
            is_admin => 1,
            media_ids => $args{media_ids},
        );

        if ( !$args{status} && ($ticket->status eq TICKET_OPEN || $ticket->status eq TICKET_IN_PROGRESS) ) {
            $ticket->set( status => TICKET_WAITING );
        }
    }

    $ticket->make_event( 'changed_ticket', settings => { action => 'update', initiator => 'admin' } ) if %update;

    return $ticket->full_info;
}

sub api_admin_delete {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->id( $args{ticket_id} );
    return unless $ticket;

    return $ticket->delete;
}

1;