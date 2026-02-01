package Core::Ticket::Tickets;

use v5.14;
use utf8;
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
            required => 1,
            title => 'ID пользователя',
        },
        subject => {
            type => 'text',
            required => 1,
            title => 'Тема тикета',
        },
        status => {
            type => 'text',
            default => 'open',
            enum => ['open', 'in_progress', 'waiting', 'closed', 'archived'],
            title => 'Статус',
        },
        priority => {
            type => 'text',
            default => 'normal',
            enum => ['low', 'normal', 'high', 'urgent'],
            title => 'Приоритет',
        },
        ticket_type => {
            type => 'text',
            default => 'other',
            enum => ['service', 'payment', 'other'],
            title => 'Тип тикета',
        },
        user_service_id => {
            type => 'number',
            title => 'ID услуги пользователя',
        },
        assigned_to => {
            type => 'number',
            title => 'Назначен на',
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
                kind => 'Ticket::Tickets',
            },
        },
    };
}

# Создать новый тикет
sub create {
    my $self = shift;
    my %args = (
        subject => 'Новое обращение',
        message => undef,
        @_,
    );

    my $user_id = $args{user_id} || $self->user_id;
    return { error => 'user_id required' } unless $user_id;

    my $ticket_id = $self->add(
        user_id => $user_id,
        subject => $args{subject},
        priority => $args{priority} || 'normal',
        ticket_type => $args{ticket_type} || 'other',
        user_service_id => $args{user_service_id},
    );
    return undef unless $ticket_id;

    my $ticket = $self->id( $ticket_id );
    return undef unless $ticket;

    if ( $args{message} ) {
        $ticket->add_message(
            message => $args{message},
            is_admin => 0,
            skip_event => 1,
        );
    }

    $self->make_event( 'changed_ticket', settings => { action => 'create', user => 1 } );

    return $ticket;
}

sub add_message {
    my $self = shift;
    my %args = (
        message => undef,
        is_admin => 0,
        media => undef,
        @_,
    );

    return undef unless $args{message};

    my $messages = get_service('Ticket::TicketMessage');
    my $msg = $messages->add(
        ticket_id => $self->id,
        user_id => $args{user_id} || $self->user_id,
        admin_id => $args{admin_id},
        message => $args{message},
        is_admin => $args{is_admin},
        media => $args{media},
    );

    $self->set( updated => now() );

    if ( !$args{is_admin} && $self->status eq 'waiting' ) {
        $self->set( status => 'open' );
    }

    unless ( $args{skip_event} ) {
        $self->make_event( 'changed_ticket', settings => { action => 'message', ($args{is_admin} ? (admin => 1) : (user => 1)) } );
    }

    return $msg;
}

sub close {
    my $self = shift;

    $self->set(
        status => 'closed',
        closed_at => now(),
    );

    $self->make_event( 'changed_ticket', settings => { action => 'close', user => 1 } );

    return $self;
}

sub archive {
    my $self = shift;

    $self->set(
        status => 'archived',
        archived_at => now(),
    );

    return $self;
}

sub messages {
    my $self = shift;

    my $messages = get_service('Ticket::TicketMessage');
    return $messages->list(
        where => { ticket_id => $self->id },
        order => [ created => 'ASC' ],
    );
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
        ticket_type => $args{ticket_type} || 'other',
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

    if ( $ticket->status eq 'closed' || $ticket->status eq 'archived' ) {
        report->add_error('Тикет закрыт');
        return undef;
    }

    return $ticket->add_message(
        message => $args{message},
        is_admin => 0,
        media => $args{media},
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
        priority => $args{priority} || 'normal',
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
    $where{assigned_to} = $args{assigned_to} if $args{assigned_to};

    return $self->list(
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
    $update{assigned_to} = $args{assigned_to} if defined $args{assigned_to};

    if ( $args{status} && $args{status} eq 'closed' ) {
        $update{closed_at} = now();
    } elsif ( $args{status} && $args{status} eq 'archived' ) {
        $update{archived_at} = now();
    }

    $ticket->set( %update ) if %update;

    if ( $args{message} ) {
        $ticket->add_message(
            message => $args{message},
            is_admin => 1,
            admin_id => $args{admin_id},
            media => $args{media},
        );

        if ( !$args{status} && ($ticket->status eq 'open' || $ticket->status eq 'in_progress') ) {
            $ticket->set( status => 'waiting' );
        }
    }

    $ticket->make_event( 'changed_ticket', settings => { action => 'update', admin => 1 } ) if %update || $args{message};

    return $ticket->full_info;
}

sub api_admin_delete {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->id( $args{ticket_id} );
    return unless $ticket;

    return $ticket->delete;
}

sub archive_old_tickets {
    my $self = shift;
    my %args = (
        days => 7,
        @_,
    );

    my $date = Core::Utils::add_date_time( days => -$args{days} );

    my @tickets = $self->_list(
        where => {
            status => 'closed',
            closed_at => { '<' => $date },
        },
    );

    for my $ticket ( @tickets ) {
        $self->id( $ticket->{ticket_id} )->archive;
    }

    return scalar @tickets;
}

sub cleanup_archived {
    my $self = shift;
    my %args = (
        days => 30,
        @_,
    );

    my $date = Core::Utils::add_date_time( days => -$args{days} );

    my @tickets = $self->_list(
        where => {
            status => 'archived',
            archived_at => { '<' => $date },
        },
    );

    for my $ticket ( @tickets ) {
        $self->id( $ticket->{ticket_id} )->delete;
    }

    return scalar @tickets;
}

1;