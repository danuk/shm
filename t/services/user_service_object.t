use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;

$ENV{SHM_TEST} = 1;

use SHM;
SHM->new( user_id => 40092 );

use Core::System::ServiceManager qw( get_service );

# Make new object of user_service
my $obj = get_service('us', _id => 99);

is ( $obj->id, 99, 'Get user_service_id' );
is ( $obj->reload, 1, 'Test reload()' );

is ( $obj->top_parent, undef, 'Test get top_parent for root service');
is ( get_service('us', _id => 665 )->top_parent->id, 99, 'Test get top_parent for child' );

is ( $obj->get_expired, '2017-01-31 23:59:50', 'Check getter for expired field' );

is ( get_service('us', _id => 101 )->parent->get_user_service_id, 99, 'Check load parent service' );

is ( $obj->set( auto_bill => 0 ), $obj->get_auto_bill == 0, 'Check service set function with cache: TEST 1');
$obj->reload;
is ( $obj->set( auto_bill => 1 ), $obj->get_auto_bill == 1, 'Check service set function with cache: TEST 2');

$obj->set( settings => { 'a' => 22 } ); # Override 'a'
$obj->set( settings => { 'b' => 33 } ); # Override 'b'
$obj->set( settings => { danuk => 'New value' } ); # Test add new value
$obj->set( settings => {} ); # Test on empty add

is_deeply( $obj->get_settings, {
    'quota' => '10000',
    'a' => 22,
    'danuk' => 'New value',
    'b' => 33
}, 'Check save settings (JSON)' );

$obj->settings->{foo}->{bar} = 1;
$obj->settings->{foo}->{biz} = 2;

$obj->settings_save;
$obj->reload;

is_deeply( $obj->settings, {
    'quota' => '10000',
    'danuk' => 'New value',
    'a' => 22,
    'b' => 33,
    'foo' => {
        'bar' => 1,
        'biz' => 2
    }
}, 'Check union settings');

done_testing();

