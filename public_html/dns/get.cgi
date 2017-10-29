#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
SHM->new();

our %in = parse_args();

unless ( $in{domain_id}=~/^\d+$/ ) {
    print_json( { status => 400 } );
    exit 0;
}

my @res = get_service('dns')->records( domain_id => $in{domain_id} );

print_json( \@res );

exit 0;
