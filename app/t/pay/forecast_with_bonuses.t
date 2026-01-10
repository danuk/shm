use v5.14;

use Test::More;
use Test::Deep;
use Core::System::ServiceManager qw( get_service );
use SHM ();
use Core::Billing;
use Data::Dumper;

$ENV{SHM_TEST} = 1;
my $user = SHM->new( user_id => 1 );

$user->set(
    bonus => 100,
    balance => 90,
    credit => 0,
    discount => 0,
);

my $service1 = get_service('service')->add(
    name => 'test service 1',
    cost => 100,
    period => 1,
    category => 'test',
    config => {
        limit_bonus_percent => 30,
    },
);

subtest 'Check forecast' => sub {
    my $bonus = $user->get_bonus;
    my $balance = $user->get_balance;

    my $us1 = create_service( service_id => $service1->id );

    my $forecast = get_service('pay')->forecast();

    cmp_deeply( $forecast, {
        items => [],
        bonuses => $bonus - 30, # withdraw 30 bonuses (30% allowed)
        balance => $balance - 70,
        total => 0,
    });
};

subtest 'Check forecast' => sub {
    my $service2 = get_service('service')->add(
        name => 'test service 2',
        cost => 100,
        period => 1,
        category => 'test',
    );

    my $bonus = $user->get_bonus;
    my $balance = $user->get_balance;

    my $us2 = create_service( service_id => $service2->id );

    my $forecast = get_service('pay')->forecast();

    cmp_deeply( $forecast, {
        items => ignore(),
        bonuses => $bonus,
        balance => $balance,
        total => 10,            # amount to be paid
    });
};

done_testing();
