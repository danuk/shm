#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
);

our %in = parse_args();

my @res = get_service('dns')->records( domain_id => $in{domain_id} );

print_json( \@res );

exit 0;
