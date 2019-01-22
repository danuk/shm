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

    my @children = @{ delete $args{children} || [] };

    my $si = $self->SUPER::add( %args );

    unless ( $si ) {
        logger->error( "Can't add new service" );
    }

    $self->subservices(
        services => [ map( $_->{service_id}, @children ) ],
    );

    return get_service('service', service_id => $si );
}

sub set {
    my $self = shift;
    my %args = (
        @_,
    );

    my @children = @{ delete $args{children} || [] };

    $self->subservices(
        services => [ map( $_->{service_id}, @children ) ],
    );

    return $self->SUPER::set( %args );
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
    my %args = (
        services => undef,
        @_,
    );

    if ( $args{services} ) {
        my $ss = get_service('SubServices');

        $ss->delete_all_for_service( $self->id );

        for ( @{ $args{services} } ) {
            $ss->add(
                service_id => $self->id,
                subservice_id => $_,
            );
        }
        return 1;
    }

    return get_service('SubServices', service_id => $self->id )->list;
}

sub delete {
    my $self = shift;
    my %args = @_;

    get_service('SubServices')->delete_all_for_service( $self->id );
    return $self->SUPER::delete( %args );
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        parent => undef,
        @_,
    );

    if ( $args{admin} && $args{parent} ) {
        my $ss = get_service('SubServices');
        my @ss_ids = $ss->_list( where => { service_id => $args{parent} } );
        unless ( @ss_ids ) {
            return ();
        }
        $args{where} = { service_id => { -in => [ map $_->{subservice_id}, @ss_ids ] } };
    }

    my @arr = $self->SUPER::list_for_api( %args );
    return @arr;
}

1;
