package Core::SubServices;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'subservices' };

sub structure {
    return {
        ss_id => '@',
        service_id => '?',
        subservice_id => '?',
    }
}

sub id {
    my $self = shift;

    unless ( $self->{service_id} ) {
        logger->error("Can't get service_id");
    }
    return $self->{service_id};
}

sub list {
    my $self = shift;

    return $self->SUPER::list( where => { service_id => $self->id } );
}

sub delete_all_for_service {
    my $self = shift;
    my $service_id = shift;

    return $self->_delete( where => { -or => [ service_id => $service_id, subservice_id => $service_id ] } );
}

1;
