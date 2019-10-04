package Core::Zones;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'zones' };

sub structure {
    return {
        zone_id => '@',
        name => '?',
        order => 0,
        server => undef,
        query => undef,
        service_id => undef,
        min_lenght => undef,
        disabled => 0,
        nic_service => undef,
        nic_template => undef,
        contract => 0,
        idn => 0,
        punycode_only => 0,
    }
}

sub list_for_api {
    my $self = shift;

    # TODO: this not supported ORDER because UserService used HASH for tree...
    #my $res = $self->SUPER::list_for_api( order => [ order => 'asc' ], @_ );
    #return my @ret = get_service('UserService')->res( $res )->with('services')->get;

    my @res = $self->SUPER::list_for_api( order => [ order => 'asc' ], @_ );

    my @services;
    push @services, $_->{service_id} for @res;

    my $services = get_service('service')->list( where => { service_id => { in => \@services } } );

    for ( @res ) {
        $_->{cost} = $services->{ $_->{service_id} }->{cost};
    }

    return @res;
}

1;
