use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;

$ENV{SHM_TEST} = 1;

use SHM;
SHM->new( user_id => 40092 );

use Core::System::ServiceManager qw( get_service );

my $service = get_service('service', _id => 1);
$service->set( cost => 5 );

my $si = get_service('service', _id => 1)->get;
is ( $si->{service_id}, 1 );
is ( $si->{cost}, 5 );
is ( $service->get_cost, 5 );

$si = get_service('service', _id => 2)->get;

is ( $si->{service_id}, 2 );
is ( $si->{cost}, 100 );

$si = $service->add( name => 'TEST', cost => 123, category => 'new' )->get;
is ( $si->{name}, 'TEST', 'Check create new service' );

subtest 'price_list_check_allow_to_order' => sub {
    my $available = get_service('service')->add(
        name => 'ALLOW ORDER TEST',
        cost => 10,
        category => 'new',
        allow_to_order => 1,
    );

    my $unavailable = get_service('service')->add(
        name => 'DISALLOW ORDER TEST',
        cost => 10,
        category => 'new',
        allow_to_order => 0,
    );

    ok( $available->price_list_check_allow_to_order, 'Service with allow_to_order=1 is present in price list items' );
    ok( !$unavailable->price_list_check_allow_to_order, 'Service with allow_to_order=0 is absent in price list items' );
};

subtest 'price_list hides already used order_only_once services' => sub {
    my $trial = get_service('service')->add(
        name => 'ORDER ONCE TEST',
        cost => 0,
        category => 'new',
        allow_to_order => 1,
        config => { order_only_once => 1 },
    );

    my @before = get_service('service')->price_list;
    ok( ( grep { $_->{service_id} == $trial->id } @before ), 'order_only_once service is present in price_list before it was ever ordered' );

    my $us = $trial->reg( service_id => $trial->id );
    ok( defined $us, 'Service is registered for the first time' );

    my @after = get_service('service')->price_list;
    ok( !( grep { $_->{service_id} == $trial->id } @after ), 'order_only_once service disappears from price_list once it was used' );

    $us->block_force;
    $us->delete;
};

is_deeply( scalar $service->categories, [
    'web_tariff_lock',
    'web_tariff',
    'web',
    'mail',
    'domain',
    'domain_prolong',
    'mysql',
    'dns',
    'domain_add',
    'transfer',
    'new',
], 'Check categories() function');

done_testing();
