package Core::Zones;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'zones' };

sub structure {
    return {
        zone_id => {
            type => 'number',
            key => 1,
        },
        name => {
            type => 'text',
            required => 1,
        },
        order => {
            type => 'number',
            default => 1,
        },
        server => {
            type => 'text',
        },
        query => {
            type => 'text',
        },
        service_id => {
            type => 'number',
        },
        min_lenght => {
            type => 'number',
        },
        disabled => {
            type => 'number',
            default => 0,
        },
        nic_service => {
            type => 'number',
        },
        nic_template => {
            type => 'number',
        },
        contract => {
            type => 'number',
            default => 0,
        },
        idn => {
            type => 'number',
            default => 0,
        },
        punycode_only => {
            type => 'number',
            default => 0,
        },
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
