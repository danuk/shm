use v5.14;

use Test::More;
use Test::Deep;

use POSIX qw(tzset);
$ENV{TZ} = 'Europe/Moscow';
tzset;

use Test::MockTime;
Test::MockTime::set_fixed_time('2016-12-31T21:00:00Z');

use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;

use SHM;
my $user = SHM->new( user_id => 40092 );

use Core::Billing;

$user->set( balance => 0, credit => 0, bonus => 0, can_overdraft => 0 );

my $service = get_service('service')->add( name => 'no credit', cost => 100, period => 1, category => 'test' );
my $service_credit = get_service('service')->add( name => 'in credit', cost => 100, period => 1, category => 'test', pay_in_credit => 1 );

my $us        = create_service( service_id => $service->id );
my $us_credit = create_service( service_id => $service_credit->id );

subtest 'Not enough money' => sub {
    is( Core::Billing::calc_payment( $us, 100 ), 0, 'without pay_in_credit service is not paid' );

    cmp_deeply( Core::Billing::calc_payment( $us_credit, 100 ), { bonus => 0, total => 100 },
        'with pay_in_credit service is paid' );
};

subtest 'can_overdraft works for all services' => sub {
    $user->set( can_overdraft => 1 );

    cmp_deeply( Core::Billing::calc_payment( $us, 100 ), { bonus => 0, total => 100 },
        'can_overdraft pays service without pay_in_credit' );

    $user->set( can_overdraft => 0 );
};

subtest 'Switch to next service uses flag of the next service' => sub {
    cmp_deeply( Core::Billing::calc_payment( $us, 100, $service_credit ), { bonus => 0, total => 100 },
        'next service with pay_in_credit is paid' );

    is( Core::Billing::calc_payment( $us_credit, 100, $service ), 0,
        'next service without pay_in_credit is not paid' );
};

subtest 'Enough money' => sub {
    $user->set( balance => 100 );

    cmp_deeply( Core::Billing::calc_payment( $us, 100 ), { bonus => 0, total => 100 },
        'service is paid when balance is enough' );
};

done_testing();
