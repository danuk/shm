package Core::Task;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw( to_json decode_json );
use Text::ParseWords 'shellwords';

sub task {
    my $self = shift;
    return $self->res;
}

sub params {
    my $self = shift;
    return $self->res->{params} || {};
}

sub event {
    my $self = shift;
    return $self->res->{event};
}

sub event_params {
    my $self = shift;

    return $self->event ? $self->event->{params} : {};
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
        if ( my $method = $self->event_params->{method} ) {
            my $kind = $self;
            if ( $self->event_params->{kind} ) {
                $kind = get_service( $self->event_params->{kind} );
            }

            if ( $kind->can( $method ) ) {
                $kind->$method();
                return $self->task_answer( TASK_SUCCESS );
            }
            else {
                return $self->task_answer( TASK_STUCK, error => 'Method not exist' );
            }
        } else {
            return $self->task_answer( TASK_STUCK, error => 'Transport not exist' );
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

        if ( $self->params->{user_service_id} ) {
            my $us = get_service('us', _id => $self->params->{user_service_id} );
            $us->set(
                settings => { server_id => $self->params->{server_id} },
            );
            $us->set_status_by_event( $self->event->{name} );
        }
    }

    return $self->task_answer( $status, %{ $response_data || {} } );
}

sub cmd {
    my $self = shift;
    my $cmd = $self->event_params->{cmd} || $self->server->get->{params}->{cmd};
    return undef unless $cmd;
}

sub make_cmd_string {
    my $self = shift;
    my $cmd = shift;

    $cmd =~s/\{\{\s*([A-Z0-9._]+)\s*\}\}/$self->_get_cmd_param($1)/gei;
    return $cmd;
}

sub make_cmd_args {
    my $self = shift;
    my $cmd = shift;

    return shellwords( $self->make_cmd_string( $cmd ) );
}

sub _get_cmd_param {
    my $self = shift;
    my $param = shift;;

    my $usi = $self->params->{user_service_id};

    my %params = (
        id =>           '$usi',
        user_id =>      'get_service("user")->get_user_id',
        us =>           'scalar get_service("us", _id => $usi)->get',
        task =>         'scalar $self->task',
        payload =>      '$self->payload',
        parent =>       'scalar get_service("us", _id => $usi)->parent->get',
        domain =>       'get_service("domain")->get_domain( user_service_id => $usi )->real_domain',
        domain_idn =>   'get_service("domain")->get_domain( user_service_id => $usi )->domain',
    );

    my ( $main_param, @md ) = split(/\./, $param );

    my $obj = $params{ lc( $main_param ) };
    return $main_param unless $obj;

    my $var = eval( $obj );

    if ( ref $var && scalar( @md ) ) {
        my $md = join('->', map( $_=~/^\d+$/ ? "[$_]" : "{$_}", @md ) );
        $var = eval( '$var->'.$md );
    }

    return ref $var ? to_json( scalar $var ) : $var;
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

    return undef unless $self->params->{server_id};

    if ( my $server = get_service('Server', _id => $self->params->{server_id} ) ) {
        return $server;
    }
    return undef;
}

sub transport_name {
    my $self = shift;

    if ( $self->event_params->{transport} ) {
        return $self->event_params->{transport};
    } elsif ( my $server = $self->server ) {
        return $server->get->{transport} || undef;
    }

    return undef;
}

sub transport {
    my $self = shift;

    return undef unless $self->params->{server_id};
    return undef unless $self->transport_name;
    return get_service( 'Transport::' . ucfirst( $self->transport_name ) );
}

sub get_service_for_transport {
    my $self = shift;

    my $service = get_service( 'Services::' . ucfirst( $self->event_params->{category} ), _id => $self->params->{user_service_id} );
    $service //= get_service( 'USObject', _id => $self->params->{user_service_id} ) if $self->params->{user_service_id};

    return $service || $self;
}

sub data_for_transport {
    my $self = shift;

    my $service = $self->get_service_for_transport;
    return $service->data_for_transport( %{ $self->params } );
}

1;
