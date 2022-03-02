package Core::System::ServiceManager;
use v5.14;

use base qw( Exporter );
our @EXPORT_OK = qw( $SERVICE_MANAGER get_service delete_service unregister_all logger $data );

our $SERVICE_MANAGER ||= new Core::System::ServiceManager();
our $data = {};

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    return $SERVICE_MANAGER if ($SERVICE_MANAGER);

    my $self = { services => {} };
    return  bless($self, $class);
}

our %AUTO_SERVICES = (
    logger => {
        class => 'Core::System::Logger',
    },
    config => {
        class => 'Core::Config',
    },
    us => {
        class => 'Core::USObject',
    },
    wd => {
        class => 'Core::Withdraw',
    },
    bill => {
        class => 'Core::Billing',
    },
);

sub is_registered {
    my $service_name = get_class_name( shift );

    if ( exists $SERVICE_MANAGER->{services}->{ $service_name } ) {
        return $SERVICE_MANAGER->{services}->{ $service_name };
    }
    return undef;
}

sub get_service {
    my $name = shift;
    my %args = @_;

    return undef unless $name;

    my $class = get_class_name( $name );
    my $service = $SERVICE_MANAGER->{services}->{ $class };
    unless ( $service ) {
        eval "require $class; 1" or return undef;
        $service = $class->new();
        return undef unless $service;
        $service->register( $class, %args );
    }

    my $service_name = $class;
    if ( $args{_id} ) {
        $service_name .= '_' . $args{_id};
    } elsif ( %args ) {
        $service_name .= '_' . join('_', map( $args{ $_ }, sort keys %args ) );
    } elsif ( $service->can('_id') ) {
        if ( my $id = $service->_id( %args ) ) {
            $service_name .= "_" . $id;
        }
    } else {
        write_log('Get service with name: ['. $service_name . ']' );
        return $service;
    }

    if ( exists $SERVICE_MANAGER->{services}->{ $service_name } ) {
        write_log('Get service with name: ['. $service_name . ']' );
        return $SERVICE_MANAGER->{services}->{ $service_name }
    }

    $service = $class->new( %{ $data||={} }, %args );
    unless ( $service ) {
        write_log('Can not create new class: ['. $service_name . '] ' );
        return undef;
    }
    $service->register( $service_name, %args );

    return $SERVICE_MANAGER->{services}->{ $service_name } ||= $service;
}

sub register_service {
    my $self = shift;
    my $service = shift;
    my $service_name = shift;
    my %args = @_;

    return undef unless $service;

    write_log("Register new service with name: [$service_name]");

    my ($package, $filename, $line, $subroutine) = caller(1);
    $self->{service_register}{ $service_name } = "$subroutine at $filename line $line";

    $self->{services}->{ $service_name } = $service;
    return $service;
}

sub delete_service {
    my $name = get_class_name( shift );

    delete $SERVICE_MANAGER->{services}->{ $name };
}

sub write_log {
    my $msg = shift;
    my $level = shift || 'debug';

    my $logger = logger();
    return unless $logger;

    $logger->$level( $msg );
}

sub logger {
    return is_registered('logger');
}


sub unregister_all {
    my $self = $SERVICE_MANAGER;

    my %protected_services = (
        config => 1,
        spool => 1,
        logger => 1,
    );

    for my $service ( keys %{ $self->{services} } ) {
        next if exists $protected_services{ $service };
        delete $self->{services}->{ $service };
        delete $self->{service_register}{ $service };
    }
}

sub unregister_service {
    my $self = shift;
    my $service = shift;

    my $id = $service->get_id();

    unless ( $self->{services}->{$id} ) {
        write_log("Service with id '" . $id . "' not registered", 'error');
        return undef;
    }

    delete $self->{services}->{$id};
    delete $self->{service_register}{$id};

    return 1;
}

sub get_class_name {
    my $name = shift;

    return $name if $name=~/^Core::/;

    if ( $AUTO_SERVICES{ $name } ) {
        return $AUTO_SERVICES{ $name }->{class};
    }
    else {
        return 'Core::' . ucfirst( $name );
    }
}

1;
