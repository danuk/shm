#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
use Core::Billing;
use Core::Utils qw(
    switch_user
);

my %res;
our %in = parse_args();

my $user = SHM->new();

# Switch to user
switch_user( $in{user_id} );

$in{settings}||= {};

if ( my $us = create_service( %in ) ) {
    ( my $obj ) = get_service('UserService')->list_for_api( usi => $us->id, admin => 1 );
    %res = %{ $obj };
}

print_header();
print_json( \%res );

exit 0;

