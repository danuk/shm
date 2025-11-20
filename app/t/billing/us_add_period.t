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

subtest 'Moneyback' => sub {
    my $service = get_service('service')->add(
        name => 'test service',
        cost => '900',
        category => 'test',
        no_discount => 1,
    );

    Test::MockTime::set_fixed_time('2019-04-01T00:00:00Z');

    my $start_balance = $user->get->{balance};
    is ( $start_balance, -21.56, 'Check start balance');

    my $us = create_service( service_id => $service->id );

    my $wd = $us->withdraw;
    cmp_deeply( scalar $wd->get,
        {
              bonus => '0',
              months => 1,
              create_date => '2019-04-01 01:00:00',
              withdraw_date => '2019-04-01 01:00:00',
              user_id => 40092,
              user_service_id => $us->id,
              qnt => 1,
              total => 900,
              end_date => '2019-05-01 01:01:59',
              cost => 900,
              service_id => $service->id,
              withdraw_id => $wd->id,
              discount => 0
          }
    , 'Check withdraw');

    my $balance_after_create = $user->get->{balance};
    is ( $balance_after_create, -921.56, 'Check balance after create');

    my $ret = $us->add_period_by_money( 450 );
    is( $ret, 1, 'Check ret status for add_period_by_money' );

    cmp_deeply( scalar $wd->get,
        {
              bonus => '0',
              months => '1.1500',
              create_date => '2019-04-01 01:00:00',
              withdraw_date => '2019-04-01 01:00:00',
              user_id => 40092,
              user_service_id => $us->id,
              qnt => 1,
              total => 900 + 450,
              end_date => '2019-05-16 01:01:59',
              cost => 900,
              service_id => $service->id,
              withdraw_id => $wd->id,
              discount => 0
        }
    , 'Check withdraw after add_period()');

    is( $us->get_expire, '2019-05-16 01:01:59', 'Check us expire date' );

    my $balance_after_money_back =  $user->get->{balance};
    is ( $balance_after_money_back, -921.56 - 450, 'Check balance after money back');
};

done_testing();
