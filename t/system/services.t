use v5.14;

use Test::More;
use Data::Dumper;

use SHM;
use Core::System::ServiceManager qw( get_service );

my $user = SHM->new( user_id => 40092 );
is ( $user->id, 40092 );

my $us = get_service('us', _id => 101 );
is ( $us->id, 101 );

my $us_parent = $us->parent;
is ( $us_parent->id, 99 );

my $ss_1 = get_service('service', _id => 1 );
my $ss_2 = get_service('service', _id => 2 );

is ( $ss_1->id, 1 );
is ( $ss_2->id, 2 );
is ( get_service('service', _id => 1)->id,  1 );
 
is ( get_service('service', _id => 1)->get->{service_id},  1 );

my $pay = get_service('pay', _id => 123, foo => 1, bar => 2 );
is ( $pay->{foo} == 1 && $pay->{bar} == 2, 1, 'Check set variables to object' );

done_testing();
