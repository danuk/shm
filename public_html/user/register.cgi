#!/usr/bin/perl

use strict;
use v5.14;

use SHM qw(:all);
my $user = SHM->new( skip_check_auth => 1 );

my %in = parse_args();

my $user_id = $user->reg(
    login => $in{login},
    password => $in{password},
);

if ( $user_id ) {
    print_json( { status => 200, msg => 'Successfully', user_id => $user_id } );
} else {
    print_json( { status => 401 } );
}

exit 0;
