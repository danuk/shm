package Core::Service;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'services' };

sub structure {
    return {
        service_id => '@',
        name => '?',
        cost => '?',
        period_cost => 1,
        category => '?',
        next => undef,
        opt => undef,
        max_count => undef,
        question => undef,
        pay_always => 1,
        no_discount => 0,
        descr => undef,
        pay_in_credit => 0,
        config => { type => 'json', value => undef },
    };
}

sub add {
    my $self = shift;
    my %args = (
        @_,
    );

    my $si = $self->SUPER::add( %args );

    unless ( $si ) {
        logger->error( "Can't add new service" );
    }

    return get_service('service', service_id => $si );
}

sub convert_name {
    my $self = shift;
    my $name = shift;
    my $settings = shift;

    $name=~s/\$\{(\w+)\}/$settings->{ $1 }/gei;
    return $name;
}

sub subservices {
    my $self = shift;
    return get_service('SubServices', service_id => $self->id )->list;
}

sub delete {
    my $self = shift;
    my %args = @_;

    get_service('SubServices')->delete_all_for_service( $self->id );
    return $self->SUPER::delete( %args );
}

1;
