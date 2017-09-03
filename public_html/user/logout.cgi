#!/usr/bin/perl

use strict;

use SHM qw(:all);
my $cli = SHM->new();

my $session = validate_session();

if ($session) {
	$session->delete();
	print_json( { status => 0, msg => 'Logout sucessfully' } );
}

exit 0;
