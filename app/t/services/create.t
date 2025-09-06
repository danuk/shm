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
    name => 'test service',
    category => 'test-category-1',
    cost => 0,
);

subtest 'Check allow_to_order' => sub {
    my $us = $service->reg(
        service_id => $service->id,
    );

    is( $us, undef );

    $service->set(allow_to_order => 1);

    $us = $service->reg(
        service_id => $service->id,
    );

    is( defined $us, 1 );
    $us->block_force;
    $us->delete;
};

subtest 'Check check_exists' => sub {
    my $us1 = $service->reg(
        service_id => $service->id,
    );
    is( defined $us1, 1 );

    my $us2 = $service->reg(
        service_id => $service->id,
        check_exists => 1,
    );
    is( defined $us2, 1 );

    is( $us1->id, $us2->id );
    $us1->block_force;
    $us1->delete;
};

subtest 'Check check_exists_unpaid' => sub {
    my $us1 = $service->reg(
        service_id => $service->id,
    );
    is( $us1->status, STATUS_ACTIVE );

    my $us2 = $service->reg(
        service_id => $service->id,
        check_exists => 1,
        check_exists_unpaid => 1,
    );
    is( defined $us2, 1 );
    is( $us1->id != $us2->id, 1 );

    $user->set( credit => 0 );
    $service->set( cost => 1000 );
    my $us3 = $service->reg(
        service_id => $service->id,
    );
    is( $us3->status, STATUS_WAIT_FOR_PAY );

    my $us4 = $service->reg(
        service_id => $service->id,
        check_exists => 1,
        check_exists_unpaid => 1,
    );
    is( $us3->id == $us4->id, 1 );

    $us1->block_force;
    $us1->delete;
    $us2->block_force;
    $us2->delete;
    $us3->block_force;
    $us3->delete;
};

subtest 'Check check_category' => sub {
    $service->set( category => 'test-test-1' );
    my $us1 = $service->reg(
        service_id => $service->id,
    );

    my $us2 = $service->reg(
        service_id => $service->id,
        check_category => 'test-test-%',
    );

    is( $us2->category eq 'test-test-1', 1 );
    is( $us1->id == $us2->id, 1 );

    my $us3 = $service->reg(
        service_id => $service->id,
        check_category => 'test-new-%',
    );
    is( $us1->id != $us3->id, 1 );

    $us1->block_force;
    $us1->delete;
    $us3->block_force;
    $us3->delete;
};

done_testing();

