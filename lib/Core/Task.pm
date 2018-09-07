package Core::Task;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw( to_json decode_json );

sub task {
    my $self = shift;
    return $self->res;
}

sub event {
    my $self = shift;
    my $e = get_service('ServicesCommands', _id => $self->task->{event_id} );
    return $e ? $e->get : undef;
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
        return $self->task_answer( TASK_DROP, error => 'Event not exists' );
    }

    my $transport = $self->transport;
    unless ( $transport ) {
        return $self->task_answer( TASK_DROP, error => 'Transport not exist' );
    }

    my ( $status, $responce_data ) = $transport->send( $self );
    unless ( $status ) {
        return $self->task_answer( TASK_FAIL, error => "Transport error", %{ $responce_data//={} } );
    }

    my $service = $self->get_service_for_transport;

    if ( $status == SUCCESS ) {
        if ( $service->can('transport_responce_data') ) {
            my ( $status, $payload ) = $service->transport_responce_data( data => $responce_data->{data} );
            unless ( $status ) {
                return $self->task_answer( TASK_DROP, error => 'Incorrect responce data', %{ $payload//={} } );
            }
        }

        if ( $self->task->{user_service_id} ) {
            my $us = get_service('us', _id => $self->task->{user_service_id} );
            $us->set(
                settings => { server_id => $self->task->{server_id} },
            );
            $us->set_status_by_event( $self->event->{event} );
        }
    }

    return $self->task_answer( $status,
        ret_code => $responce_data->{ret_code},
        data => $responce_data->{data},
        error => $responce_data->{error},
    );
}

sub cmd {
    my $self = shift;
    my $cmd = $self->event->{params}->{cmd} || $self->server->get->{params}->{cmd};
    return undef unless $cmd;
}

sub make_cmd_string {
    my $self = shift;
    my $cmd = shift;

    return join(' ', $self->make_cmd_args( $cmd ) );
}

sub make_cmd_args {
    my $self = shift;
    my $cmd = shift;

    my @args;
    for my $value ( split(/\s+/, $cmd ) ) {
        $value =~s/\$\{([A-Z0-9_.]+)\}/$self->_get_cmd_param($1)/gei;
        push @args, $value;
    }
    return @args;
}

sub _get_cmd_param {
    my $self = shift;
    my $param = shift;;

    my $usi = $self->task->{user_service_id};

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
        responce => {
            %args,
        }
    }
}

sub server {
    my $self = shift;

    my $server = get_service('Server', _id => $self->task->{server_id} );
    return undef unless $server;
}

sub transport_name {
    my $self = shift;

    return exists $self->event->{params}->{transport} ? $self->event->{params}->{transport} : $self->server->get->{transport};
}

sub transport {
    my $self = shift;

    return undef unless $self->task->{server_id};
    return get_service( 'Transport::' . ucfirst( $self->transport_name ) );
}

sub get_service_for_transport {
    my $self = shift;

    my $service = get_service( 'Services::' . ucfirst( $self->event->{category} ), _id => $self->task->{user_service_id} );
    $service //= get_service( 'USObject', _id => $self->task->{user_service_id} ) if $self->task->{user_service_id};

    return $service || $self;
}

sub data_for_transport {
    my $self = shift;

    my $service = $self->get_service_for_transport;
    return $service->data_for_transport( $self->task );
}

1;
