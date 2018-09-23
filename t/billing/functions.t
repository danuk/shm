use v5.14;

use Test::More;
use Data::Dumper;
use Core::Billing;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $us = SHM->new( user_id => 40092 );

is( Core::Billing::get_service_discount( service_id => 1 ), 0, 'get service discount percent' );
is( Core::Billing::get_service_discount( months => 2, service_id => 1 ), 0, 'get service discount percent' );
is( Core::Billing::get_service_discount( months => 3, service_id => 1 ), 10, 'get service discount percent' );

is( Core::Billing::get_service_discount( service_id => 11 ), 0, 'get service discount percent for domain' );
is( Core::Billing::get_service_discount( months => 12, service_id => 11 ), 0, 'get service discount percent for domain' );
is( Core::Billing::get_service_discount( months => 24, service_id => 11 ), 0, 'get service discount percent for domain' );
is( Core::Billing::get_service_discount( months => 11, service_id => 11 ), 0, 'get service discount percent for domain' );

get_service('user')->set( discount => 13 );
is( Core::Billing::get_service_discount( service_id => 1 ), 13, 'get service discount percent' );

done_testing();
