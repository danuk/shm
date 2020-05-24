package Core::Task;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub task {
    my $self = shift;
    return $self->res;
}

sub settings {
    my $self = shift;
    return $self->res->{settings} || {};
}

sub event {
    my $self = shift;
    return $self->res->{event};
}

sub event_settings {
    my $self = shift;

    return $self->event ? $self->event->{settings} : {};
}

sub payload {
    my $self = shift;

    my ( $status, $payload ) = $self->data_for_transport;
    return $status ? $payload : undef;
}

sub make_task {
    my $self = shift;

    my %info;

    unless ( $self->event ) {
        return $self->task_answer( TASK_STUCK, error => 'Event not exists' );
    }

    my $transport = $self->transport;
    unless ( $transport ) {
        if ( my $method = $self->event->{method} ) {
            my $kind = $self;
            if ( $self->event->{kind} ) {
                $kind = get_service( $self->event->{kind} );
            }

            if ( $kind->can( $method ) ) {
                $kind->$method();
                return $self->task_answer( TASK_SUCCESS );
            }
            else {
                return $self->task_answer( TASK_STUCK, error => 'Method not exist' );
            }
        } else {
            return $self->task_answer( TASK_STUCK, error => 'Transport not exists' );
        }
    }

    my ( $status, $response_data ) = $transport->send( $self );
    unless ( $status ) {
        return $self->task_answer( TASK_FAIL, error => "Transport error", %{ $response_data//={} } );
    }

    my $service = $self->get_service_for_transport;

    if ( $status == SUCCESS ) {
        if ( $service->can('transport_response_data') ) {
            my ( $status, $payload ) = $service->transport_response_data( %{ $response_data || {} } );
            unless ( $status ) {
                return $self->task_answer( TASK_STUCK, error => 'Incorrect response data', %{ $payload//={} } );
            }
        }

        if ( $self->settings->{user_service_id} ) {
            my $us = get_service('us', _id => $self->settings->{user_service_id} );
            $us->set(
                settings => { server_id => $self->settings->{server_id} },
            );
            $us->set_status_by_event( $self->event->{name} );
        }
    }

    return $self->task_answer( $status ? TASK_SUCCESS : TASK_FAIL, %{ $response_data || {} } );
}

sub cmd {
    my $self = shift;
    my $cmd = $self->event_settings->{cmd} || $self->server->get->{settings}->{cmd};
    return undef unless $cmd;
}

sub task_answer {
    my $self = shift;
    my $status = shift;
    my %args = @_;

    return $status, {
        response => {
            %args,
        }
    }
}

sub server {
    my $self = shift;

    return undef unless $self->settings->{server_id};

    if ( my $server = get_service('Server', _id => $self->settings->{server_id} ) ) {
        return $server;
    }
    return undef;
}

sub transport_name {
    my $self = shift;

    if ( $self->event_settings->{transport} ) {
        return $self->event_settings->{transport};
    } elsif ( my $server = $self->server ) {
        return $server->get->{transport} || undef;
    }

    return undef;
}

sub transport {
    my $self = shift;

    return undef unless $self->settings->{server_id};
    return undef unless $self->transport_name;
    return get_service( 'Transport::' . ucfirst( $self->transport_name ) );
}

sub get_service_for_transport {
    my $self = shift;

    my $service = get_service( 'Services::' . ucfirst( $self->event_settings->{category} ), _id => $self->settings->{user_service_id} );
    $service //= get_service( 'USObject', _id => $self->settings->{user_service_id} ) if $self->settings->{user_service_id};

    return $service || $self;
}

sub data_for_transport {
    my $self = shift;

    my $service = $self->get_service_for_transport;
    return $service->data_for_transport( %{ $self->settings } );
}

1;
