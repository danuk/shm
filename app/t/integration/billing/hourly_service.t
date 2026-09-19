use v5.14;

use Test::More;
use Test::Deep;
use Test::MockTime;
use Core::Billing;
use POSIX qw(tzset);

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

$ENV{TZ} = 'Europe/London'; # UTC+0
tzset;

Test::MockTime::set_fixed_time('2024-01-01T00:00:00Z');

subtest 'Create service with cost=1 and period=0.0001 (1 hour)' => sub {
    $user->set( balance => 10, credit => 0, discount => 0 );
    is( $user->get_balance, 10, 'Check start balance' );

    my $si = get_service('service')->add(
        name        => 'Hourly test service',
        cost        => 1,
        period      => 0.0001,
        category    => 'test',
        no_discount => 1,
    );

    ok( $si->id, 'Service created with id=' . $si->id );

    my $us = create_service( service_id => $si->id, months => 0.0001 );
    ok( defined $us, 'User service created' );

    my $wd = $us->wd;
    is( $wd->get_total,  1,      'Total == 1 rub' );
    is( $wd->get_cost,   1,      'Cost == 1 rub' );
    is( $wd->get_months, 0.0001, 'Months == 0.0001' );

    is( $user->get_balance, 9, 'Balance decreased by 1 rub' );
};

subtest 'Order the same service for 2 hours' => sub {
    my $si = get_service('service')->add(
        name        => 'Hourly test service 2h',
        cost        => 1,
        period      => 0.0001,
        category    => 'test',
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id, months => 0.0002 );
    ok( defined $us, 'User service created' );

    my $wd = $us->wd;
    is( $wd->get_total,  2,      'Total == 2 rub' );
    is( $wd->get_cost,   1,      'Cost == 1 rub (price per period)' );
    is( $wd->get_months, 0.0002, 'Months == 0.0002 (2 hours)' );

    is( $user->get_balance, 7, 'Balance decreased by 2 rub' );
};

subtest 'Create service with cost=1 and period=0.01 (1 day)' => sub {
    $user->set( balance => 10, credit => 0, discount => 0 );

    my $si = get_service('service')->add(
        name        => 'Daily test service',
        cost        => 1,
        period      => 0.01,
        category    => 'test',
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id, months => 0.01 );
    ok( defined $us, 'User service created' );

    my $wd = $us->wd;
    is( $wd->get_total,  1,    'Total == 1 rub' );
    is( $wd->get_cost,   1,    'Cost == 1 rub' );
    is( $wd->get_months, 0.01, 'Months == 0.01 (1 day)' );

    is( $user->get_balance, 9, 'Balance decreased by 1 rub' );
};

subtest 'Order the daily service for 2 days' => sub {
    $user->set( balance => 10, credit => 0, discount => 0 );

    my $si = get_service('service')->add(
        name        => 'Daily test service 2d',
        cost        => 1,
        period      => 0.01,
        category    => 'test',
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id, months => 0.02 );
    ok( defined $us, 'User service created' );

    my $wd = $us->wd;
    is( $wd->get_total,  2,    'Total == 2 rub' );
    is( $wd->get_cost,   1,    'Cost == 1 rub (price per period)' );
    is( $wd->get_months, 0.02, 'Months == 0.02 (2 days)' );

    is( $user->get_balance, 8, 'Balance decreased by 2 rub' );
};

subtest 'Create service with cost=1 and period=0.0203 (2 days 3 hours)' => sub {
    $user->set( balance => 10, credit => 0, discount => 0 );

    my $si = get_service('service')->add(
        name        => 'Hybrid test service',
        cost        => 1,
        period      => 0.0203,
        category    => 'test',
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id, months => 0.0203 );
    ok( defined $us, 'User service created' );

    my $wd = $us->wd;
    is( $wd->get_total,  1,      'Total == 1 rub (shortcut months==period)' );
    is( $wd->get_cost,   1,      'Cost == 1 rub' );
    is( $wd->get_months, 0.0203, 'Months == 0.0203 (2d3h)' );

    is( $user->get_balance, 9, 'Balance decreased by 1 rub' );
};

subtest 'Order the hybrid service for 2 periods (4 days 6 hours)' => sub {
    $user->set( balance => 10, credit => 0, discount => 0 );

    my $si = get_service('service')->add(
        name        => 'Hybrid test service 2x',
        cost        => 1,
        period      => 0.0203,
        category    => 'test',
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id, months => 0.0406 );
    ok( defined $us, 'User service created' );

    my $wd = $us->wd;
    is( $wd->get_total,  2,      'Total == 2 rub' );
    is( $wd->get_cost,   1,      'Cost == 1 rub (price per period)' );
    is( $wd->get_months, 0.0406, 'Months == 0.0406 (4d6h)' );

    is( $user->get_balance, 8, 'Balance decreased by 2 rub' );
};

subtest 'Create service with cost=1 and period=1.0203 (1 month 2 days 3 hours)' => sub {
    $user->set( balance => 10, credit => 0, discount => 0 );

    my $si = get_service('service')->add(
        name        => 'Monthly+days+hours test service',
        cost        => 1,
        period      => '1.0203',
        category    => 'test',
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id, months => '1.0203' );
    ok( defined $us, 'User service created' );

    my $wd = $us->wd;
    is( $wd->get_total,  1,      'Total == 1 rub (shortcut months==period)' );
    is( $wd->get_cost,   1,      'Cost == 1 rub' );
    is( $wd->get_months, 1.0203, 'Months == 1.0203 (1m2d3h)' );

    is( $user->get_balance, 9, 'Balance decreased by 1 rub' );
};

subtest 'Order the monthly+days+hours service for 2 periods' => sub {
    $user->set( balance => 10, credit => 0, discount => 0 );

    my $si = get_service('service')->add(
        name        => 'Monthly+days+hours test service 2x',
        cost        => 1,
        period      => '1.0203',
        category    => 'test',
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id, months => '2.0406' );
    ok( defined $us, 'User service created' );

    my $wd = $us->wd;
    is( $wd->get_total,  2.01,   'Total == 2.01 rub (minor calendar rounding)' );
    is( $wd->get_cost,   1,      'Cost == 1 rub (price per period)' );
    is( $wd->get_months, 2.0406, 'Months == 2.0406 (2m4d6h)' );

    is( $user->get_balance, 7.99, 'Balance decreased by 2.01 rub' );
};

done_testing();
