#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

our %in = parse_args();

my $domain = get_service('domain');

my $domain_id = $domain->add(
    type => 0,
    domain => $in{domain},
);

unless ( $domain_id ) {
    print_json( { msg =>'domain already exists', result => 1 } );
    exit 0;
}

use Core::Billing qw/create_service/;
my $us = create_service( service_id => 63 );

if ( blessed $us ) {
    my @children = map( $_->{user_service_id}, $us->children );

    for ( @children ) {
        get_service('us', _id => $_ )->add_domain( domain_id => $domain_id );
    }
}
else {
    print_json( { status => 503 } );
    exit 0;
}

print_json( { msg => 'successful', result => 0 } );

exit 0;
