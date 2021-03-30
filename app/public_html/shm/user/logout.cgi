#!/usr/bin/perl

use v5.14;
use SHM qw(:all);

my $user = SHM->new( skip_check_auth => 1 );

if ( my $session = validate_session() ) {
	$session->delete();
}

print_json( { status => 0, msg => 'Logout sucessfully' } );

exit 0;
