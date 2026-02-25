use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Billing::Simpler qw(
    calc_end_date_by_months
    calc_total_by_date_range
    calc_period_by_total
);

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $us = SHM->new( user_id => 40092 );

is( calc_end_date_by_months('2017-01-01 00:00:00', 1), '2017-01-30 23:59:59', 'Test calc_end_date_by_months 1');
is( calc_end_date_by_months('2017-07-01 00:00:00', 1), '2017-07-30 23:59:59', 'Test calc_end_date_by_months 2');
is( calc_end_date_by_months('2017-07-02 00:00:00', 1), '2017-07-31 23:59:59', 'Test calc_end_date_by_months 3');

is( calc_end_date_by_months('2017-02-01 00:00:00', 1), '2017-03-02 23:59:59', 'Test calc_end_date_by_months 4');
is( calc_end_date_by_months('2017-02-01 00:00:01', 1), '2017-03-03 00:00:00', 'Test calc_end_date_by_months 5');

is( calc_end_date_by_months('2017-01-10 12:33:00', 1), '2017-02-09 12:32:59', 'Test calc_end_date_by_months 6');

is( calc_end_date_by_months('2017-01-01 00:00:00', 2), '2017-03-01 23:59:59', 'Test calc_end_date_by_months 6');
is( calc_end_date_by_months('2017-01-01 00:00:00', 3), '2017-03-31 23:59:59', 'Test calc_end_date_by_months 7');

is( calc_end_date_by_months('2017-02-05 00:00:00', 1), '2017-03-06 23:59:59', 'Test calc_end_date_by_months 8');

is( calc_end_date_by_months('2017-02-27 00:00:00', 1), '2017-03-28 23:59:59', 'Test calc_end_date_by_months 9');
is( calc_end_date_by_months('2017-03-29 18:51:25', 1), '2017-04-28 18:51:24', 'Test calc_end_date_by_months 10');
is( calc_end_date_by_months('2017-04-28 20:34:16', 1), '2017-05-28 20:34:15', 'Test calc_end_date_by_months 11');

is( calc_end_date_by_months('2017-01-01 00:00:00', '0.1'), '2017-01-10 23:59:59', 'Test calc_end_date_by_months 12');
is( calc_end_date_by_months('2017-01-01 00:00:00', '0.10'), '2017-01-10 23:59:59', 'Test calc_end_date_by_months');
is( calc_end_date_by_months('2017-01-01 00:00:00', '0.1001'), '2017-01-11 00:59:59', 'Test calc_end_date_by_months');
is( calc_end_date_by_months('2017-01-01 00:00:00', '0.01'), '2017-01-01 23:59:59', 'Test calc_end_date_by_months 13');
is( calc_end_date_by_months('2017-01-01 00:00:00', '0.0100'), '2017-01-01 23:59:59', 'Test calc_end_date_by_months');
is( calc_end_date_by_months('2017-01-01 00:00:00', '0.0101'), '2017-01-02 00:59:59', 'Test calc_end_date_by_months');

is( calc_end_date_by_months('2017-01-01 00:00:00', '0.0001'), '2017-01-01 00:59:59', 'Test calc_end_date_by_months');
is( calc_end_date_by_months('2017-01-01 00:00:00', '0.0010'), '2017-01-01 09:59:59', 'Test calc_end_date_by_months');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-01 23:59:59',
        cost            => '900',
    ),
    {
        total => '30.00',
        months => '0.0100',
    }
,'calc_total_by_date_range (one day without one second)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-02 00:00:00',
        cost            => '900',
    ),
    {
        total => '30.00',
        months => '0.0100',
    }
,'calc_total_by_date_range (one day)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-01 08:00:00',
        cost            => '900',
    ),
    {
        total => '10.00',
        months => '0.0008',
    }
,'calc_total_by_date_range (third part of day)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-30 23:59:59',
        cost            => '1000',
    ),
    {
        total => '1000.00',
        months => '1.0000',
    }
,'calc_total_by_date_range (30 days)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-03-01 23:59:59',
        cost            => '1000',
    ),
    {
        total => '2000.00',
        months => '2.0000',
    }
,'calc_total_by_date_range (60 days)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-02-09 12:33:00',
        cost            => '1000',
    ),
    {
        total => '1000.00',
        months => '1.0000',
    }
,'calc_total_by_date_range (30 days in other months)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-02-10 12:33:00',
        cost            => '1000',
    ),
    {
        total => '1033.33',
        months => '1.0100',
    }
,'calc_total_by_date_range (31 day)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-10-31 00:00:00',
        end_date        => '2018-02-01 23:59:59',
        cost            => '3100',
    ),
    {
        total => '9713.33',
        months => '3.0400',
    }
,'calc_total_by_date_range (jump to next year)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-30 23:59:59',
        cost            => 30,
        period     => 0.01,
    ),
    {
        total => '900.00',
        months => '1.0000',
    }
,'calc_total_by_date_range (with period)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-31 01:00:00',
        cost            => 1,
        period     => 0.0001,
    ),
    {
        total => '721.00',
        months => '1.0001',
    }
,'calc_total_by_date_range (with period)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-31 01:00:00',
        cost            => 0,
        period     => 1,
    ),
    {
        total => '0.00',
        months => '1.0001',
    }
,'calc_total_by_date_range (calc zero cost)');

# Tests for calc_period_by_total
is( calc_period_by_total(
        total => 100,
        cost => 1000,
        period => 1
    ), '0.0300', 'calc_period_by_total: 100 out of 1000 per month'
);

is( calc_period_by_total(
        total => 250,
        cost => 1000,
        period => 1
    ), '0.0712', 'calc_period_by_total: quarter month'
);

is( calc_period_by_total(
        total => 500,
        cost => 1000,
        period => 1
    ), '0.1500', 'calc_period_by_total: half month'
);

is( calc_period_by_total(
        total => 1000,
        cost => 1000,
        period => 1
    ), '1.0000', 'calc_period_by_total: full month'
);

is( calc_period_by_total(
        total => 1500,
        cost => 1000,
        period => 1
    ), '1.1500', 'calc_period_by_total: month and half'
);

is( calc_period_by_total(
        total => 50,
        cost => 300,
        period => '1.1500'
    ), '0.0712', 'calc_period_by_total: fractional period 1.1500'
);

is( calc_period_by_total(
        total => 25,
        cost => 100,
        period => '0.1012'
    ), '0.0215', 'calc_period_by_total: small fractional period'
);

is( calc_period_by_total(
        total => 30,
        cost => 900,
        period => 1
    ), '0.0100', 'calc_period_by_total: one day worth'
);

is( calc_period_by_total(
        total => 10,
        cost => 900,
        period => 1
    ), '0.0008', 'calc_period_by_total: 8 hours worth'
);

# Edge cases
is( calc_period_by_total(
        total => 0,
        cost => 1000,
        period => 1
    ), '0.0000', 'calc_period_by_total: zero total'
);

is( calc_period_by_total(
        total => 100,
        cost => 0,
        period => 1
    ), '0.0000', 'calc_period_by_total: zero cost'
);

is( calc_period_by_total(
        total => 100,
        cost => undef,
        period => 1
    ), '0.0000', 'calc_period_by_total: undefined cost'
);

is( calc_period_by_total(
        total => undef,
        cost => 1000,
        period => 1
    ), '0.0000', 'calc_period_by_total: undefined total'
);

# Test with period 0.01 (1 day) - if cost is 30 for 1 day, and total is 30, we get 1 day
is( calc_period_by_total(
        total => 30,
        cost => 30,
        period => 0.01
    ), '0.0100', 'calc_period_by_total: period 0.01 (1 day tariff)'
);

# Test with period 0.0001 (1 hour) - if cost is 1 for 1 hour, and total is 1, we get 1 hour
is( calc_period_by_total(
        total => 1,
        cost => 1,
        period => 0.0001
    ), '0.0001', 'calc_period_by_total: period 0.0001 (1 hour tariff)'
);

# Test precision with small amounts - 1.25 out of 30 per month
is( calc_period_by_total(
        total => 1.25,
        cost => 30,
        period => 1
    ), '0.0106', 'calc_period_by_total: small amount precision'
);

# Reverse compatibility tests - calc_period_by_total should give results that work with calc_total_by_date_range
# Test: 333.33 out of 1000 should give ~10 days, and calc_total_by_date_range for 10 days should give ~333.33
my $reverse_period = calc_period_by_total(
    total => 333.33,
    cost => 1000,
    period => 1
);
is( $reverse_period, '0.1000', 'calc_period_by_total: reverse compatibility check period' );

# Test that calc_total_by_date_range with fractional period works as expected
cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-11 00:00:00',  # 10 days
        cost            => 1000,
        period          => 1
    ),
    {
        total => '333.33',
        months => '0.1000',
    }
,'calc_total_by_date_range: 10 days should cost 333.33'
);

# Test with very small period - actual calculation: 0.5/30*30*24 = 12 hours = 0.0012
is( calc_period_by_total(
        total => 0.5,
        cost => 30,
        period => 1
    ), '0.0012', 'calc_period_by_total: very small amount - 12 hours'
);

# Test multi-month calculation
is( calc_period_by_total(
        total => 3000,
        cost => 1000,
        period => 1
    ), '3.0000', 'calc_period_by_total: 3 months worth'
);

# Test with complex fractional period input - actual result based on calculation
is( calc_period_by_total(
        total => 150,
        cost => 500,
        period => '2.1012'  # 2 months, 10 days, 12 hours
    ), '0.2104', 'calc_period_by_total: complex fractional period input'
);

done_testing();
