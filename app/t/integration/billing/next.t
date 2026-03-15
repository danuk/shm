use v5.14;

use Test::More;
use Test::MockTime;
use Test::Deep;
use Core::Billing;
use POSIX qw(tzset);

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(now);
use SHM;
my $user = SHM->new( user_id => 40092 );

$ENV{TZ} = 'Europe/London'; #UTC+0
tzset;

my $next_next_service = get_service('service')->add(
    name => 'next next service',
    cost => '200',
    period => 1,
    category => 'test',
    no_discount => 1,
);

my $next_service = get_service('service')->add(
    name => 'next service',
    cost => '100',
    period => 1,
    category => 'test',
    no_discount => 1,
    next => $next_next_service->id,
);

my $test_service = get_service('service')->add(
    name => 'test service',
    cost => '0',
    period => '0.01',
    category => 'test',
    no_discount => 1,
    next => $next_service->id,
);

Test::MockTime::set_fixed_time('2019-04-01T00:00:00Z');
my $start_balance = $user->get->{balance};
my $us = create_service( service_id => $test_service->id );

is( $us->get_expire, '2019-04-02 00:59:59');
is( $us->get_next, $next_service->id );

subtest 'create test service with next' => sub {
    my $wd = $us->withdraw;
    cmp_deeply( scalar $wd->get,
        {
              'user_id' => 40092,
              'months' => 0.01,
              'qnt' => 1,
              'bonus' => '0',
              'discount' => 0,
              'cost' => '0',
              'total' => 0,
              'create_date' => '2019-04-01 01:00:00',
              'withdraw_date' => '2019-04-01 01:00:00',
              'end_date' => '2019-04-02 00:59:59',
              'user_service_id' => $us->id,
              'service_id' => $test_service->id,
              'withdraw_id' => $wd->id,
          }
    , 'Check withdraw');

    my $balance_after_create = $user->get->{balance};
    is ( $balance_after_create, $start_balance, 'Check balance after create');
};

subtest 'check switch test service to next' => sub {
    Test::MockTime::set_fixed_time('2019-04-03T00:00:00Z');

    my $start_balance = $user->get->{balance};

    $us->touch();
    is( $us->get_expire, '2019-05-02 01:49:57');
    is( $us->get_service_id, $next_service->id );
    is( $us->get_next, $next_next_service->id );

    my $wd = $us->withdraw;
    cmp_deeply( scalar $wd->get,
        {
              'user_id' => 40092,
              'months' => 1,
              'qnt' => 1,
              'bonus' => '0',
              'discount' => 0,
              'cost' => 100,
              'total' => 100,
              'create_date' =>   '2019-04-03 01:00:00',
              'withdraw_date' => '2019-04-03 01:00:00',
              'end_date' =>      '2019-05-02 01:49:57',
              'user_service_id' => $us->id,
              'service_id' => $next_service->id,
              'withdraw_id' => $wd->id,
          }
    , 'Check withdraw for next service');

    my $balance_after_create = $user->get->{balance};
    is ( $balance_after_create, $start_balance - 100, 'Check balance after switch');
};

subtest 'Check switch test service to next (6 months)' => sub {
    Test::MockTime::set_fixed_time('2019-05-03T00:00:00Z');

    my $next_service = get_service('service')->add(
        name => 'next service for 6 months',
        cost => '600',
        period => 6,
        category => 'test',
        no_discount => 1,
    );

    is( $us->wd->months, 1 );
    is( $us->wd->cost, 100 );
    is( $us->wd->total, 100 );

    $us->set( next => $next_service->id );

    $us->touch();
    is( $us->get_expire, '2019-11-02 00:59:56');
    is( $us->get_next, 0 );

    my $wd = $us->withdraw;
    cmp_deeply( scalar $wd->get,
        {
              'user_id' => 40092,
              'months' => 6,
              'qnt' => 1,
              'bonus' => '0',
              'discount' => 0,
              'cost' => 600,
              'total' => 600,
              'create_date' =>   '2019-05-03 01:00:00',
              'withdraw_date' => '2019-05-03 01:00:00',
              'end_date' =>      '2019-11-02 00:59:56',
              'user_service_id' => $us->id,
              'service_id' => $next_service->id,
              'withdraw_id' => $wd->id,
          }
    , 'Check withdraw for next service');
};

subtest 'create test service with next (without payment)' => sub {
    Test::MockTime::set_fixed_time('2019-04-01T00:00:00Z');
    $user->set( balance => 0, credit => 0 );
    my $us = create_service( service_id => $test_service->id );

    is( $us->get_status, 'ACTIVE' );
    is( $us->get_expire, '2019-04-02 00:59:59');
    is( $us->get_next, $next_service->id );

    Test::MockTime::set_fixed_time('2019-04-03T00:00:00Z');
    $us->touch();
    is( $us->get_status, 'BLOCK' );
    is( $us->get_expire, '2019-04-02 00:59:59');
    is( $us->get_service_id, $next_service->id );
    is( $us->get_next, $next_next_service->id );

    $user->payment( money => 200 );
    $us->touch();
    is( $us->get_status, 'ACTIVE' );
    is( $us->get_expire, '2019-05-03 02:37:59');
    is( $us->get_service_id, $next_service->id );
    is( $us->get_next, $next_next_service->id );
};

subtest 'allow_partial_renew: renew for partial period when insufficient funds' => sub {
    Test::MockTime::set_fixed_time('2019-10-01T00:00:00Z');

    my $partial_service = get_service('service')->add(
        name        => 'allow_partial_renew service',
        cost        => '100',
        period      => 1,
        category    => 'test',
        no_discount => 1,
        config      => { allow_partial_renew => 1 },
    );

    $user->set( balance => 100, credit => 0 );
    my $us = create_service( service_id => $partial_service->id );

    is( $us->get_status, 'ACTIVE',              'Service is active after creation' );
    is( $us->get_expire, '2019-11-01 00:58:02', 'Expire after first full period' );
    is( $user->get->{balance}, 0,               'Balance after full payment' );

    # Время истечения, у пользователя только половина суммы
    Test::MockTime::set_fixed_time('2019-11-02T00:00:00Z');
    $user->set( balance => 50, credit => 0 );

    $us->touch();

    is( $us->get_status, 'ACTIVE',              'Service is active after partial renewal' );
    is( $us->get_expire, '2019-11-17 00:58:01', 'Expire after partial period (16 days)' );
    is( $us->wd->months,  '0.16',               'Withdraw has partial months (16 days)' );
    is( $us->wd->total,   50,                   'Withdraw total equals available balance' );
    is( $user->get->{balance}, 0,               'Balance fully consumed after partial renewal' );
};

subtest 'allow_partial_renew: renew for partial period with balance and bonus' => sub {
    Test::MockTime::set_fixed_time('2019-10-01T00:00:00Z');

    my $partial_service = get_service('service')->add(
        name        => 'allow_partial_renew service with bonus',
        cost        => '100',
        period      => 1,
        category    => 'test',
        no_discount => 1,
        config      => { allow_partial_renew => 1 },
    );

    $user->set( balance => 100, bonus => 0, credit => 0 );
    my $us = create_service( service_id => $partial_service->id );

    is( $us->get_status, 'ACTIVE',              'Service is active after creation' );
    is( $us->get_expire, '2019-11-01 00:58:02', 'Expire after first full period' );
    is( $user->get_balance, 0,                  'Balance after full payment' );

    # Время истечения, у пользователя недостаточно денег, но есть бонусы
    # баланс=30, бонусы=20, итого=50 -> 16 дней
    Test::MockTime::set_fixed_time('2019-11-02T00:00:00Z');
    $user->set( balance => 30, bonus => 20, credit => 0 );

    $us->touch();

    is( $us->get_status,       'ACTIVE',              'Service is active after partial renewal' );
    is( $us->get_expire,       '2019-11-17 00:58:01', 'Expire after partial period (16 days)' );
    is( $us->wd->months,       '0.16',                'Withdraw has partial months (16 days)' );
    is( $us->wd->total,        30,                    'Withdraw total equals balance charged' );
    is( $us->wd->get_bonus,    20,                    'Withdraw bonus equals bonus charged' );
    is( $user->get_balance,    0,                     'Balance fully consumed after partial renewal' );
    is( $user->get_bonus,      0,                     'Bonus fully consumed after partial renewal' );
};

done_testing();
