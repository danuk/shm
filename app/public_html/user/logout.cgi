#!/usr/bin/perl

use v5.14;
use SHM qw(:all);

my $user = SHM->new();

my $session = validate_session();

if ($session) {
	$session->delete();
	print_json( { status => 0, msg => 'Logout sucessfully' } );
}

exit 0;
