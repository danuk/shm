use strict;
use warnings;

use v5.14;
use Test::More;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );
use Core::Const;

$ENV{SHM_TEST} = 1;

use SHM;
my $user = SHM->new( user_id => 40092 );

my $service = get_service('service')->add(
    name => 'test service 1',
    category => 'test-category-1',
    cost => 200,
    allow_to_order => 1,
);

my $service_next = get_service('service')->add(
    name => 'test service 2',
    category => 'test-category-1',
    cost => 100,
    allow_to_order => 1,
    next => 1,
);

subtest 'Check WAIT_FOR_PAY -> WAIT_FOR_PAY' => sub {
    $user->set( balance => 10, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_WAIT_FOR_PAY);
    is( $us->withdraw->total, $service->cost );
    is ( $us->get_next, 0 );

    $us->change( service_id => $service_next->id );

    is ( $us->service_id, $service_next->id );
    is ( $us->status, STATUS_WAIT_FOR_PAY);
    is( $us->withdraw->total, $service_next->cost );
    is ( $us->get_next, 1 );
};

subtest 'Check WAIT_FOR_PAY -> ACTIVE' => sub {
    $user->set( balance => 100, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_WAIT_FOR_PAY);
    is( $us->withdraw->total, $service->cost );

    $us->change( service_id => $service_next->id );

    is ( $us->service_id, $service_next->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service_next->cost );
};

subtest 'Check ACTIVE -> BLOCK -> ACTIVE' => sub {
    $user->set( balance => 200, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service->cost );
    is ( $user->balance, 0 );

    $user->set( balance => -200, credit => 0 );
    $us->change( service_id => $service_next->id );

    is ( $us->service_id, $service_next->id );
    is ( $us->status, STATUS_BLOCK);
    is( $us->withdraw->total, $service_next->cost );
    is ( $user->balance, 0 );

    $user->set( balance => 200, credit => 0 );
    $us->change( service_id => $service->id );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service->cost );
    is ( $user->balance, 0 );
};

subtest 'Check ACTIVE -> ACTIVE' => sub {
    $user->set( balance => 200, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service->cost );
    is ( $user->balance, 0 );

    $us->change( service_id => $service_next->id );

    is ( $us->service_id, $service_next->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service_next->cost );
    is ( $user->balance, 100 );
};

done_testing();

