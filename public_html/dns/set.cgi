#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
SHM->new();

our %in = parse_args();

unless ( $in{domain_id}=~/^\d+$/ ) {
    print_json( { status => 400 } );
    exit 0;
}

my $id = get_service('dns')->add( %in );

unless ( $id ) {
    print_json( { status => 400 } );
    exit 0;
}

print_json( { status => 200, record_id => $id } );

exit 0;
