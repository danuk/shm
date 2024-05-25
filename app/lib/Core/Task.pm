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
    return $self->res->{event} || {};
}

sub event_settings {
    my $self = shift;

    return $self->event->{settings} || {};
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

    if ( my $method = $self->event->{method} ) {
        my $kind = $self;
        if ( $self->event->{kind} ) {
            unless ( $kind = $self->srv( $self->event->{kind} ) ) {
                return $self->task_answer( TASK_STUCK, error => 'Kind not found' );
            }
        }

        if ( $kind->can( $method ) ) {
            my ( $status, $response_data ) = $kind->$method( $self );
            unless ( $status ) {
                return $self->task_answer( TASK_STUCK, error => "Method error", %{ $response_data//={} } );
            } else {
                return $self->task_answer( TASK_SUCCESS, %{ $response_data//={} } );
            }
        }
        else {
            return $self->task_answer( TASK_STUCK, error => 'Method not exist' );
        }
    }

    my $transport = $self->transport;
    unless ( $transport ) {
        return $self->task_answer( TASK_STUCK, error => 'Transport not exists' );
    }

    my ( $status, $response_data ) = $transport->send( $self );
    if ( !defined $status ) {
        return $self->task_answer( TASK_STUCK, %{ $response_data//={} } );
    }

    if ( $status == FAIL ) {
        return $self->task_answer( TASK_FAIL, error => 'Transport error', %{ $response_data//={} } );
    } elsif ( $status == SUCCESS ) {
        my $service = $self->get_service_for_transport;
        if ( $service->can('transport_response_data') ) {
            my ( $status, $payload ) = $service->transport_response_data( %{ $response_data || {} } );
            unless ( $status ) {
                return $self->task_answer( TASK_STUCK, error => 'Incorrect response data', %{ $payload//={} } );
            }
        }

        if ( my $usi = $self->settings->{user_service_id} ) {
            my $us = $self->srv('us', _id => $usi );

            if ( !$us->settings->{server_id} &&
                 $response_data &&
                 $response_data->{server} &&
                 $response_data->{server}->{id}
             ) {
                $us->settings( { server_id => $self->server_id } )->settings_save();
                if ( my $server = $self->server ) {
                    $server->services_count_increase;
                }
            }

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

    my $logger_level = $status eq TASK_SUCCESS ? 'debug' : 'error';
    logger->$logger_level( 'TASK ANSWER:', $status,  %args );

    return $status, {
        response => {
            %args,
        }
    }
}

sub server_id {
    my $self = shift;

    return $self->settings->{server_id} || $self->event_settings->{server_id};
}

sub server {
    my $self = shift;
    my %args = (
        transport => undef,
        @_,
    );

    unless ( $self->server_id ) {
        if ( my $transport_name = $args{transport} ) {
            if ( my @server_ids = $self->srv('Server')->list_by_transport( $transport_name ) ) {
                return $self->srv('Server', _id => $server_ids[0]->{server_id} );
            }
        }
        return undef;
    }

    if ( my $server = $self->srv('Server', _id => $self->server_id ) ) {
        return $server;
    }
    return undef;
}

sub transport_name {
    my $self = shift;

    if ( my $transport = $self->event_settings->{transport} ) {
        return $transport;
    } elsif ( my $server_gid = $self->event->{server_gid} ) {
        my $ServerGroups = $self->srv('ServerGroups', _id => $server_gid );
        return undef unless $ServerGroups;
        return $ServerGroups->get->{transport};
    } elsif ( my $server = $self->server ) {
        return $server->get->{transport} || undef;
    }

    return undef;
}

sub transport {
    my $self = shift;

    return undef unless $self->transport_name;
    return $self->srv( 'Transport::' . ucfirst( $self->transport_name ) );
}

sub get_service_for_transport {
    my $self = shift;

    #my $service = $self->srv( 'Services::' . ucfirst( $self->event_settings->{category} ), _id => $self->settings->{user_service_id} );
    my $service = $self->srv( 'USObject', _id => $self->settings->{user_service_id} ) if $self->settings->{user_service_id};

    return $service || $self;
}

sub data_for_transport {
    my $self = shift;

    my $service = $self->get_service_for_transport;
    return $service->data_for_transport( %{ $self->settings } );
}

1;
