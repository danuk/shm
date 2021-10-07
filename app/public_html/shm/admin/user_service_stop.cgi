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

my $us = get_service('us', _id => $in{user_service_id});

if ( $us ) {
    $us->stop();
}

print_header();
print_json( scalar $us->get );

$user->commit;

exit 0;

