#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

my %in = parse_args();

sub usage {
	print_json( {status => 400, msg => "Use 'action' and 'usi' params"} );
    exit 1;
}

usage unless ( $in{action} && $in{usi} );

print_json( $user->services->id( $in{usi} )->settings->get );

exit 0;

