use v5.14;

use Test::More;
use Test::MockTime;
use Test::Deep;
use Core::Billing;
use POSIX qw(tzset);
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(now);
use SHM;
my $user = SHM->new( user_id => 40092 );

$ENV{TZ} = 'Europe/London'; #UTC+0
tzset;

my $cost_sub_service = 10;
my $cost_service = 100;

my $sub_service = get_service('service')->add(
    name => 'paid sub service',
    cost => $cost_sub_service,
    period => 1,
    category => 'test',
    no_discount => 1,
);

my $service = get_service('service')->add(
    name => 'test service',
    cost => $cost_service,
    period => '1',
    category => 'test',
    no_discount => 1,
    children => [
        {
            service_id => $sub_service->id,
            qnt => 2,
        },
    ],
);

Test::MockTime::set_fixed_time('2019-04-01T00:00:00Z');

my $start_balance = $user->get_balance;
my $us = create_service( service_id => $service->id );
my $balance_after_create = $user->get_balance;

is( $us->get_expire, '2019-05-01 01:01:59');

is ( $balance_after_create, $start_balance - $cost_service - $cost_sub_service * 2, 'Check balance after create');

subtest 'Check service' => sub {
    cmp_deeply( scalar $us->get,
        {
            'parent' => undef,
            'service_id' => $service->id,
            'status' => 'ACTIVE',
            'next' => 0,
            'created' => '2019-04-01 01:00:00',
            'expire' => '2019-05-01 01:01:59',
            'auto_bill' => 1,
            'user_id' => 40092,
            'withdraw_id' => ignore(),
            'user_service_id' => ignore(),
            'settings' => undef,
        }
    , 'Check user service');

    my $wd = $us->withdraw;
    cmp_deeply( scalar $wd->get,
        {
              'user_id' => 40092,
              'months' => 1,
              'qnt' => 1,
              'bonus' => '0',
              'discount' => 0,
              'cost' => $cost_service,
              'total' => $cost_service,
              'create_date' => '2019-04-01 01:00:00',
              'withdraw_date' => '2019-04-01 01:00:00',
              'end_date' => '2019-05-01 01:01:59',
              'user_service_id' => $us->id,
              'service_id' => $service->id,
              'withdraw_id' => $wd->id,
        }
    , 'Check service withdraw');

};

my ( $child ) = $us->children;
my $us_child = get_service('us', _id => $child->{user_service_id} );

subtest 'Check sub service' => sub {
    cmp_deeply( scalar $us_child->get,
        {
            'parent' => $us->id,
            'service_id' => $sub_service->id,
            'status' => 'ACTIVE',
            'next' => 0,
            'created' => '2019-04-01 01:00:00',
            'expire' => '2019-05-01 01:01:59',
            'auto_bill' => 1,
            'user_id' => 40092,
            'withdraw_id' => ignore(),
            'user_service_id' => ignore(),
            'settings' => undef,
        }
    , 'Check sub user service');

    my $sub_wd = $us_child->withdraw;
    cmp_deeply( scalar $sub_wd->get,
        {
              'user_id' => 40092,
              'months' => 1,
              'qnt' => 2,
              'bonus' => '0',
              'discount' => 0,
              'cost' => $cost_sub_service,
              'total' => $cost_sub_service * 2,
              'create_date' => '2019-04-01 01:00:00',
              'withdraw_date' => '2019-04-01 01:00:00',
              'end_date' => '2019-05-01 01:01:59',
              'user_service_id' => $us_child->id,
              'service_id' => $sub_service->id,
              'withdraw_id' => $sub_wd->id,
        }
    , 'Check sub withdraw');
};

subtest 'Check prolongate user service' => sub {
    Test::MockTime::set_fixed_time('2019-05-03T00:00:00Z');

    my $start_balance = $user->get_balance;
    $us->touch();

    my $balance_after_create = $user->get_balance;

    is( $us->get_expire, '2019-06-01 00:59:58');

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
              'create_date' =>   '2019-05-03 01:00:00',
              'withdraw_date' => '2019-05-03 01:00:00',
              'end_date' =>      '2019-06-01 00:59:58',
              'user_service_id' => $us->id,
              'service_id' => $service->id,
              'withdraw_id' => $wd->id,
          }
    , 'Check withdraw for next service');

    my $sub_wd = $us_child->withdraw;
    cmp_deeply( scalar $sub_wd->get,
        {
              'user_id' => 40092,
              'months' => 1,
              'qnt' => 2,
              'bonus' => '0',
              'discount' => 0,
              'cost' => $cost_sub_service,
              'total' => $cost_sub_service * 2,
              'create_date' => '2019-05-03 01:00:00',
              'withdraw_date' => '2019-05-03 01:00:00',
              'end_date' => '2019-06-01 00:59:58',
              'user_service_id' => $us_child->id,
              'service_id' => $sub_service->id,
              'withdraw_id' => $sub_wd->id,
        }
    , 'Check sub withdraw');
};


subtest 'Check old style sub services' => sub {
    my $old_service = get_service('service')->add(
        name => 'test old service',
        cost => 1,
        category => 'test',
        children => [30,31],
    );

    cmp_deeply( $old_service->subservices, [
        {
            service_id => 30,
            qnt => 1,
        },
        {
            service_id => 31,
            qnt => 1,
        },
    ]);
};

subtest 'Check `qnt` for api_subservices_list' => sub {
    cmp_deeply( $service->api_subservices_list,
    {
          'pay_in_credit' => 0,
          'config' => undef,
          'next' => 0,
          'allow_to_order' => undef,
          'question' => undef,
          'category' => 'test',
          'cost' => '10',
          'pay_always' => 1,
          'name' => 'paid sub service',
          'service_id' => $sub_service->id,
          'children' => undef,
          'period' => '1',
          'no_discount' => 1,
          'max_count' => undef,
          'deleted' => 0,
          'qnt' => 2,
          'descr' => undef,
          'is_composite' => 0
    }, '');
};

done_testing();
