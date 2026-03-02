use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;

use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;

use SHM;
my $us = SHM->new( user_id => 40092 );

my $d = get_service('discounts');

is( $d->get_by_period( months => 1 )->{months}, 1 );
is( $d->get_by_period( months => 2 )->{months}, 1 );
is( $d->get_by_period( months => 3 )->{months}, 3 );
is( $d->get_by_period( months => 4 )->{months}, 3 );
is( $d->get_by_period( months => 5 )->{months}, 3 );
is( $d->get_by_period( months => 6 )->{months}, 6 );
is( $d->get_by_period( months => 7 )->{months}, 6 );
is( $d->get_by_period( months => 8 )->{months}, 6 );
is( $d->get_by_period( months => 9 )->{months}, 6 );
is( $d->get_by_period( months => 10 )->{months}, 6 );
is( $d->get_by_period( months => 11 )->{months}, 6 );
is( $d->get_by_period( months => 12 )->{months}, 12 );
is( $d->get_by_period( months => 13 )->{months}, 12 );


done_testing();
