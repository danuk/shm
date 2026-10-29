use v5.14;

use Test::More;
use Test::Deep;

use POSIX qw(tzset);
$ENV{TZ} = 'Europe/Moscow';
tzset;

use Test::MockTime;
Test::MockTime::set_fixed_time('2016-12-31T21:00:00Z'); # Sun Jan  1 00:00:00 2017

use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;

use SHM;
my $user = SHM->new( user_id => 40092 );

use Core::Billing;

# Неполный период: лимит бонусов (limit_bonus_percent) считается от суммы списания, а не от баланса

my $service_limit = get_service('service')->add( name => 'limit 50', cost => 1000, period => 1, category => 'test',
    config => { limit_bonus_percent => 50 } );
my $service_free = get_service('service')->add( name => 'no limit', cost => 1000, period => 1, category => 'test' );

my $us = create_service( service_id => $service_free->id );

sub partial {
    my $service = shift;
    my %wd = ( cost => 1000, total => 1000, months => 1 );
    Core::Billing::apply_partial_period( $us, \%wd, 1, $service );
    return \%wd;
}

subtest 'Limit 50%: bonuses are half of the total' => sub {
    $user->set( balance => 100, bonus => 1000, credit => 0, can_overdraft => 0 );

    my $wd = partial( $service_limit );
    is( $wd->{total}, 200, 'total = balance / (1 - 50%)' );
    cmp_deeply( Core::Billing::calc_payment( $us, $wd->{total}, $service_limit ), { bonus => 100, total => 100 },
        'payment: 100 bonuses + 100 money' );
};

subtest 'Limit 50%: not enough bonuses' => sub {
    $user->set( balance => 100, bonus => 30 );

    my $wd = partial( $service_limit );
    is( $wd->{total}, 130, 'total = balance + all bonuses' );
    cmp_deeply( Core::Billing::calc_payment( $us, $wd->{total}, $service_limit ), { bonus => 30, total => 100 },
        'payment: 30 bonuses + 100 money' );
};

subtest 'Limit 30%: total is rounded down' => sub {
    my $service_30 = get_service('service')->add( name => 'limit 30', cost => 1000, period => 1, category => 'test',
        config => { limit_bonus_percent => 30 } );
    $user->set( balance => 100, bonus => 1000 );

    my $wd = partial( $service_30 );
    is( $wd->{total}, 142.85, 'total = 100 / 0.7 rounded down' );
    my $pay = Core::Billing::calc_payment( $us, $wd->{total}, $service_30 );
    ok( $pay && $pay->{total} <= 100, 'money part does not exceed balance' );
};

subtest 'Without limit: balance + all bonuses' => sub {
    $user->set( balance => 100, bonus => 50 );

    my $wd = partial( $service_free );
    is( $wd->{total}, 150, 'total = balance + bonuses' );
};

subtest 'Negative balance: debt reduces the total' => sub {
    $user->set( balance => -50, bonus => 100 );

    my $wd = partial( $service_free );
    is( $wd->{total}, 50, 'total = balance + bonuses' );
    ok( Core::Billing::calc_payment( $us, $wd->{total}, $service_free ), 'payment is possible' );

    my $wd_limit = partial( $service_limit );
    is( $wd_limit->{total}, 1000, 'with limit debt must be paid by money: withdraw is not changed' );
};

subtest 'Debt bigger than bonuses: nothing to pay (both billings)' => sub {
    $user->set( balance => -50, bonus => 0 );

    for my $billing (qw( Honest Simpler )) {
        no warnings 'redefine';
        local *Core::USObject::billing = sub { $billing };

        my $wd = partial( $service_free );
        is( $wd->{total}, 1000, "$billing: withdraw is not changed" );
        is( $wd->{months}, 1, "$billing: months are not changed" );
    }
};

subtest 'Without money and without bonuses: nothing to pay (both billings)' => sub {
    $user->set( balance => 0, bonus => 0 );

    for my $billing (qw( Honest Simpler )) {
        no warnings 'redefine';
        local *Core::USObject::billing = sub { $billing };

        my $wd = partial( $service_free );
        is( $wd->{total}, 1000, "$billing: withdraw is not changed" );
    }
};

subtest 'Credit is used like in calc_payment' => sub {
    $user->set( balance => 100, credit => 300, bonus => 0 );

    my $wd = partial( $service_free );
    is( $wd->{total}, 400, 'total = balance + credit' );
    ok( Core::Billing::calc_payment( $us, $wd->{total}, $service_free ), 'payment is possible' );

    $user->set( balance => -50, credit => 300 );
    $wd = partial( $service_free );
    is( $wd->{total}, 250, 'debt is covered by credit: total = balance + credit' );
    ok( Core::Billing::calc_payment( $us, $wd->{total}, $service_free ), 'payment is possible' );

    $user->set( balance => 100, credit => 100, bonus => 1000 );
    $wd = partial( $service_limit );
    is( $wd->{total}, 400, 'limit 50%: (balance + credit) / (1 - 50%)' );
    cmp_deeply( Core::Billing::calc_payment( $us, $wd->{total}, $service_limit ), { bonus => 200, total => 200 },
        'payment: 200 bonuses + 200 money' );

    $user->set( balance => -500, credit => 300, bonus => 0 );
    $wd = partial( $service_free );
    is( $wd->{total}, 1000, 'debt bigger than credit: withdraw is not changed' );

    $user->set( credit => 0 );
};

subtest 'Without money and with limit: nothing to pay' => sub {
    $user->set( balance => 0, bonus => 1000 );

    my $wd = partial( $service_limit );
    is( $wd->{total}, 1000, 'withdraw is not changed' );
};

done_testing();
