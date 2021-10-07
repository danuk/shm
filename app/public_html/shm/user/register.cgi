#!/usr/bin/perl

use strict;
use v5.14;

use SHM qw(:all);
my $user = SHM->new( skip_check_auth => 1 );

my %in = parse_args();

my $object = $user->reg( %in );

if ( $object ) {
    my %user = $object->get;
    delete $user{password};
    print_json( { status => 200, %user } );
} else {
    print_json( { status => 400 } );
}

$user->commit;

exit 0;
