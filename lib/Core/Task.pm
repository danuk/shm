package Core::Task;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub make_task {
    my $self = shift;

    my %info;
    my %task = $self->res;

    my $transport = $self->get_transport;
    unless ( $transport ) {
        return $self->task_answer( TASK_DROP, error => 'Transport not exist' );
    }

    my $service = $self->get_service_for_transport;

    my ( $status, $payload ) = $service->data_for_transport( %task );
    unless ( $status ) {
        return $self->task_answer( TASK_DROP, error => "Can't get data for transport", %{ $payload//={} } );
    }

    my ( $status, $responce_data ) = $transport->send(
        %task,
        payload => $payload,
    );
    unless ( $status ) {
        return $self->task_answer( TASK_FAIL, error => "Transport error", %{ $responce_data//={} } );
    }

    if ( $status == SUCCESS && $service->can('transport_responce_data') ) {
        ( $status, $payload ) = $service->transport_responce_data( data => $responce_data->{data} );
        unless ( $status ) {
            return $self->task_answer( TASK_DROP, error => 'Incorrect responce data', %{ $payload//={} } );
        }
    }

    return $self->task_answer( $status,
        ret_code => $responce_data->{ret_code},
        data => $responce_data->{data},
        error => $responce_data->{error},
    );
}

sub task_answer {
    my $self = shift;
    my $status = shift;
    my %args = @_;

    return $status, {
        responce => {
            %args,
        }
    }
}

sub get_transport {
    my $self = shift;

    my $server_id = $self->res->{server_id};
    return undef unless $server_id;

    my $server = get_service('Server', _id => $server_id )->get;
    return undef unless $server;

    return get_service( 'Transport::' . ucfirst( $server->{transport} ) );
}

sub get_service_for_transport {
    my $self = shift;

    my %task = $self->res;
    my $service = get_service( 'Services::' . ucfirst( $task{category} ), _id => $task{user_service_id} );
    $service //= get_service( 'USObject', _id => $task{user_service_id} ) if $task{user_service_id};

    return $service || $self;
}

sub data_for_transport { return SUCCESS, shift->res->{data} ;}

1;
