package Core::System::ServiceManager;
use v5.14;

=module Core::System::ServiceManager

=head1 Название

Менеджер сервисов. Синглетон. Автоматом создается при импорте модуля.

Предлагает на экспорт функцию get_service, выдающую по идентификатору сервис,
зарегистрированный в менеджере сервисов.

=head1 Функции

=cut

use base qw( Exporter );
our @EXPORT_OK = qw( $SERVICE_MANAGER get_service delete_service unregister_all logger $data );

our $SERVICE_MANAGER ||= new Core::System::ServiceManager();
our $data = {};

=head2 new

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    return $SERVICE_MANAGER if ($SERVICE_MANAGER);

    my $self = { services => {} };
    return  bless($self, $class);
}

=head2 get_service

Выдает по идентификатору зарегистрированный в себе сервис.

=cut

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
    my $service_name = shift;

    if ( exists $SERVICE_MANAGER->{services}->{ $service_name } ) {
        return $SERVICE_MANAGER->{services}->{ $service_name };
    }
    return undef;
}

sub get_service {
    my $name = shift;
    my %args = @_;

    return undef unless $name;

    # Set _id to 0 for undefined services
    if ( defined $args{_id} && $args{_id} eq '' ) {
        $args{_id} = 0;
    }

    my $service_name = $name;
    if ( $args{_id} ) {
        $service_name .= '_' . $args{_id};
    } elsif ( %args ) {
        $service_name .= '_' . join('_', map( $args{ $_ }, sort keys %args ) );
    }

    if ( exists $SERVICE_MANAGER->{services}->{ $service_name } ) {
        write_log('Get service with name: ['. $service_name . ']' );
        return $SERVICE_MANAGER->{services}->{ $service_name }
    }

    # Получаем реальный name от самого сервиса и новый экзмелпяр сервиса
    # или undef если сервис с таким name уже зарегистрирован
    ( $name, my $service ) = $SERVICE_MANAGER->auto_service( $name, %args );
    unless ( $name ) {
        write_log('Get service with name: ['. $service_name . '] - not exists' );
        return undef;
    }

    write_log('Get service with name: ['. $name . ']' );

    return $SERVICE_MANAGER->{services}->{ $name } ||= $service;
}

sub delete_service {
    my $name = shift;

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

sub auto_service {
    my $self = shift;
    my $name = shift;
    my %args = @_;
    my %info;

    if ( $AUTO_SERVICES{ $name } ) {
        %info = %{ $AUTO_SERVICES{ $name } };
    }
    else {
        $info{class} = 'Core::' . ucfirst( $name );
    }

    for ( @{ $info{required}||= [] } ) {
        die "$_ required but not loaded" unless get_service( $_ );
    }

    eval "require $info{class}; 1" or return undef;

    my $service = $info{class}->new( %{ $data||={} }, %args );
    unless ( $service ) {
        return undef;
    }
    $name = $service->register( $name, %args );
    return $name, $service;
}

=pod

=head2 register_service

На вход принимает сервис. Регистрирует его в себе по идентификатору сервиса.

=cut

sub register_service {
    my $self = shift;
    my $service = shift;
    my $name = shift;
    my %args = @_;

    # Получаем актуальный name, сгенерированный загруженным модулем
    if ( $service->can( '_id' ) ) {
        $name = $service->_id( %args );
    } elsif ( exists $args{_id} ) {
        $name .= '_' . $args{_id};
    } elsif ( %args ) {
        $name .= '_' . join('_', map( $args{ $_ }, sort keys %args ) );
    }

    unless ( $name ) {
        die "Can't get name for service";
    }

    if ( $self->{services}->{$name} ) {
        # Сервис уже зарегистирован, выгружаем его копию, т.к. он уже есть
        undef $service; # TODO: проверить что сервис так выгрузился
        return $name;
    }

    $self->{services}->{$name} = $service;
    my ($package, $filename, $line, $subroutine) = caller(1);

    $self->{service_register}{$name} = "$subroutine at $filename line $line";

    write_log("Register new service with name: [$name]");

    return $name;
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

=pod

=head2 unregister_service

На вход принимает сервис. Разегистрирует его в себе по идентификатору сервиса.

=cut

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

1;
