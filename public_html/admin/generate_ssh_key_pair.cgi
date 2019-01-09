#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Core::System::ServiceManager qw( get_service );

my $service = get_service( 'identities' );

my %res = $service->generate_key_pair();

print_header();
print_json( \%res );

exit 0;

