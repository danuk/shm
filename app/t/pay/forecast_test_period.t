use v5.14;

use Test::More;
use Test::Deep;
use Core::System::ServiceManager qw( get_service );
use SHM ();
use Core::Billing;

$ENV{SHM_TEST} = 1;
my $user = SHM->new( user_id => 40094 );

$user->set( balance => 0, bonus => 0, credit => 0, discount => 10 );

my $service = get_service('service')->add(
    name => 'test service',
    cost => 100,
    period => 1,
    category => 'test',
);

my $test_service = get_service('service')->add(
    name => 'test period of service',
    cost => 0,
    period => 0.03,
    category => 'test',
    next => $service->id,
);

my $us = create_service( service_id => $test_service->id );

my $ret = get_service('pay')->forecast();

cmp_deeply( $ret, {
    items => bag(
        {
            name => 'test period of service',
            months => 0.03,
            qnt => 1,
            cost => 0,
            discount => 10,
            total => 0,
            service_id => $test_service->id,
            usi => $us->id,
            user_service_id => $us->id,
            expire => ignore(),
            status => 'ACTIVE',
            next => {
                name => 'test service',
                service_id => $service->id,
                months => 1,
                cost => 100,
                discount => 10,
                total => 90,
                qnt => 1,
            },
        },
    ),
    balance => 0,
    bonuses => 0,
    dept => 0,
    total => 90,
});

done_testing();
