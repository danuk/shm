use v5.14;

use Test::More;
use Test::Deep;
use Core::Billing;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

my $test_service = get_service('service')->add(
    name => 'test service',
    cost => '100',
    period => '6',
    category => 'test',
);

$user->set( credit => 0 );
my $us = create_service( service_id => $test_service->id );

subtest 'Check recalc() for UNPAID' => sub {
    is( $us->get_status, 'NOT PAID' );
    is( $us->wd->get_cost, 100 );
    is( $us->wd->get_total, 100 );
    is( $us->wd->get_months, 6 );
    is( $us->wd->get_discount, 0 );
    is( $us->wd->get_user_service_id, $us->id );

    $user->set( discount => 20 );

    $us->recalc();

    is( $us->get_status, 'NOT PAID' );
    is( $us->wd->get_cost, 100 );
    is( $us->wd->get_total, 80 );
    is( $us->wd->get_months, 6 );
    is( $us->wd->get_discount, 20 );
    is( $us->wd->get_user_service_id, $us->id );
};

done_testing();
