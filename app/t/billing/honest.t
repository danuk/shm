use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Billing::Honest qw(
    calc_month_cost
    calc_end_date_by_months
    calc_total_by_date_range
    calc_period_by_total
);

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $us = SHM->new( user_id => 40092 );

is( calc_end_date_by_months('2017-01-01 00:00:00', 1), '2017-01-31 23:59:59', 'Test calc_end_date_by_months 1');
is( calc_end_date_by_months('2017-07-01 00:00:00', 1), '2017-07-31 23:59:59', 'Test calc_end_date_by_months 2');
is( calc_end_date_by_months('2017-07-02 00:00:00', 1), '2017-08-01 23:59:59', 'Test calc_end_date_by_months 3');

is( calc_end_date_by_months('2017-02-01 00:00:00', 1), '2017-02-28 23:59:59', 'Test calc_end_date_by_months 4');
is( calc_end_date_by_months('2017-02-01 00:00:01', 1), '2017-03-01 00:00:00', 'Test calc_end_date_by_months 5');

is( calc_end_date_by_months('2017-01-10 12:33:00', 1), '2017-02-09 14:25:55', 'Test calc_end_date_by_months 6');

is( calc_end_date_by_months('2017-01-01 00:00:00', 2), '2017-02-28 23:59:59', 'Test calc_end_date_by_months 6');
is( calc_end_date_by_months('2017-01-01 00:00:00', 3), '2017-03-31 23:59:59', 'Test calc_end_date_by_months 7');

is( calc_end_date_by_months('2017-02-05 00:00:00', 1), '2017-03-05 10:17:07', 'Test calc_end_date_by_months 8');

is( calc_end_date_by_months('2017-02-27 00:00:00', 1), '2017-03-29 18:51:24', 'Test calc_end_date_by_months 9');
is( calc_end_date_by_months('2017-03-29 18:51:25', 1), '2017-04-28 20:34:15', 'Test calc_end_date_by_months 10');
is( calc_end_date_by_months('2017-04-28 20:34:16', 1), '2017-05-29 18:51:23', 'Test calc_end_date_by_months 11');

is( calc_end_date_by_months('2017-01-01 00:00:00', '0.1'), '2017-01-10 23:59:59', 'Test calc_end_date_by_months 12');
is( calc_end_date_by_months('2017-01-01 00:00:00', '0.01'), '2017-01-01 23:59:59', 'Test calc_end_date_by_months 13');

is( calc_end_date_by_months('2017-01-01 00:00:00', '0.0101'), '2017-01-02 00:59:59', 'Test calc_end_date_by_months');

is( calc_end_date_by_months('2023-11-19 22:17:12', '1'), '2023-12-20 13:25:45');
is( calc_end_date_by_months('2023-11-19 22:17:12', '2'), '2024-01-20 13:25:45');
is( calc_end_date_by_months('2023-11-19 22:17:12', '12'), '2024-11-19 22:17:11');
is( calc_end_date_by_months('2025-10-11 06:37:40', '12'), '2026-10-11 06:37:39');

is_deeply( calc_month_cost( from_date => '2017-04-01 00:00:00', cost => '3000' ), {
    start => '2017-04-01 00:00:00',
    stop => '2017-04-30 23:59:59',
    total => '3000.00',
},'calc_month_cost: from_date (1 month)');

is_deeply( calc_month_cost( from_date => '2017-04-30 23:59:59', cost => '3000' ), {
    start => '2017-04-30 23:59:59',
    stop => '2017-04-30 23:59:59',
    total => '0.00',
},'calc_month_cost: from_date (0 day)');

is_deeply( calc_month_cost( from_date => '2017-04-30 00:00:00', cost => '3000' ), {
    start => '2017-04-30 00:00:00',
    stop => '2017-04-30 23:59:59',
    total => '100.00',
},'calc_month_cost: from_date (1 day)');

is_deeply( calc_month_cost( to_date => '2017-04-30 23:59:59', cost => '3000' ), {
    start => '2017-04-01 00:00:00',
    stop => '2017-04-30 23:59:59',
    total => '3000.00',
},'calc_month_cost: to_date (0 day)');

is_deeply( calc_month_cost( to_date => '2017-04-09 23:59:59', cost => '3000' ), {
    start => '2017-04-01 00:00:00',
    stop => '2017-04-09 23:59:59',
    total => '900.00',
},'calc_month_cost: to_date (9 day)');


cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-31 23:59:59',
        cost            => '1000',
    ),
    {
        total => '1000.00',
        months => '1.00',
    }
,'calc_total_by_date_range');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-02-01 00:00:00',
        cost            => '1000',
    ),
    {
        total => '1000.00',
        months => '1.00',
    }
,'calc_total_by_date_range');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-02-28 23:59:59',
        cost            => '1000',
    ),
    {
        total => '2000.00',
        months => '2.00',
    }
,'calc_total_by_date_range');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-03-01 00:00:00',
        cost            => '1000',
    ),
    {
        total => '2000.00',
        months => '2.00',
    }
,'calc_total_by_date_range');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-04-30 23:59:59',
        cost            => '1000',
    ),
    {
        total => '4000.00',
        months => '4.00',
    }
,'calc_total_by_date_range');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-04-10 12:33:00',
        cost            => '1000',
    ),
    {
        total => '3010.24',
        months => '3.00',
    }
,'calc_total_by_date_range');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-05-10 12:33:00',
        cost            => '1000',
    ),
    {
        total => '4000.00',
        months => '4.00',
    }
,'calc_total_by_date_range');

# Проверяем, что между двумя датами, различающихся на один месяц,
# списание не месячное (более 1000 руб.). Это правильно, т.к. в месяцах разное кол-во дней
cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-02-10 12:33:00',
        cost            => '1000',
    ),
    {
        total => '1032.91',
        months => '1.00',
    }
,'calc_total_by_date_range');

# Ранее, к дате списания прибавил месяц, и получил дату окончания
# Проверяем, что между этими двумя датами списание равно месячному.
# Эта ф-ия является обратной к calc_end_date_by_months
cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-02-09 14:25:55',
        cost            => '1000',
    ),
    {
        total => '1000.00',
        months => '0.30', # TODO: fix me: must been '1.00'
    }
,'calc_total_by_date_range');

# Вычисляем стоимость короткого периода (для двух дней)
cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-02 23:59:59',
        cost            => '3100',
    ),
    {
        total => '200.00',
        months => '0.02',
    }
,'calc_total_by_date_range (2 days on start month)');

# Вычисляем стоимость короткого периода (для двух дней)
cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 00:00:00',
        end_date        => '2017-01-11 23:59:59',
        cost            => '3100',
    ),
    {
        total => '200.00',
        months => '0.02',
    }
,'calc_total_by_date_range (2 days in middle)');

# Вычисляем стоимость короткого периода (для двух дней с переходом месяца)
cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-31 00:00:00',
        end_date        => '2017-02-01 23:59:59',
        cost            => '3100',
    ),
    {
        total => '210.71',
        months => '0.02',
    }
,'calc_total_by_date_range (2 days with jump to next month)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-10-31 00:00:00',
        end_date        => '2018-02-01 23:59:59',
        cost            => '3100',
    ),
    {
        total => '9510.71',
        months => '3.02',
    }
,'calc_total_by_date_range (jump to next year)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-10-31 00:00:00',
        end_date        => '2018-02-01 23:59:59',
        cost            => '0',
    ),
    {
        total => '0.00',
        months => '3.02',
    }
,'calc_total_by_date_range (calc zero cost)');

# Tests for calc_period_by_total (Honest billing with calendar days)
is( calc_period_by_total(
        total => 500,
        cost => 1000,
        period => 1,
        reference_date => '2017-01-01 00:00:00'
    ), '0.16', 'calc_period_by_total: half cost in January (31 days)'
);

is( calc_period_by_total(
        total => 500,
        cost => 1000,
        period => 1,
        reference_date => '2017-02-01 00:00:00'
    ), '0.15', 'calc_period_by_total: half cost in February (28 days)'
);

is( calc_period_by_total(
        total => 500,
        cost => 1000,
        period => 1,
        reference_date => '2016-02-01 00:00:00'  # leap year
    ), '0.15', 'calc_period_by_total: half cost in February leap year (29 days)'
);

is( calc_period_by_total(
        total => 1000,
        cost => 1000,
        period => 1,
        reference_date => '2017-01-01 00:00:00'
    ), '1.00', 'calc_period_by_total: full month cost'
);

is( calc_period_by_total(
        total => 2000,
        cost => 1000,
        period => 1,
        reference_date => '2017-01-01 00:00:00'
    ), '2.00', 'calc_period_by_total: two months cost'
);

is( calc_period_by_total(
        total => 1500,
        cost => 1000,
        period => 1,
        reference_date => '2017-01-01 00:00:00'
    ), '1.15', 'calc_period_by_total: 1.5 months cost'
);

is( calc_period_by_total(
        total => 100,
        cost => 3100,
        period => 1,
        reference_date => '2017-01-01 00:00:00'
    ), '0.01', 'calc_period_by_total: small amount - should be 1 day'
);

# Edge cases
is( calc_period_by_total(
        total => 0,
        cost => 1000,
        period => 1
    ), '0.00', 'calc_period_by_total: zero total'
);

is( calc_period_by_total(
        total => 100,
        cost => 0,
        period => 1
    ), '0.00', 'calc_period_by_total: zero cost'
);

is( calc_period_by_total(
        total => 100,
        cost => undef,
        period => 1
    ), '0.00', 'calc_period_by_total: undefined cost'
);

is( calc_period_by_total(
        total => undef,
        cost => 1000,
        period => 1
    ), '0.00', 'calc_period_by_total: undefined total'
);

# Test with different periods
is( calc_period_by_total(
        total => 100,
        cost => 300,
        period => 3,  # 300 for 3 months = 100 per month
        reference_date => '2017-01-01 00:00:00'
    ), '1.00', 'calc_period_by_total: fractional period - 3 months'
);

# Test different months to show calendar effect
is( calc_period_by_total(
        total => 1000,
        cost => 3100,
        period => 1,
        reference_date => '2017-04-01 00:00:00'  # April has 30 days
    ), '0.10', 'calc_period_by_total: April (30 days) - should get ~10 days'
);

is( calc_period_by_total(
        total => 3000,
        cost => 3100,
        period => 1,
        reference_date => '2017-01-01 00:00:00'  # January has 31 days
    ), '0.30', 'calc_period_by_total: January (31 days) - should get ~30 days'
);

# Test month transition - cost spans multiple months
is( calc_period_by_total(
        total => 3500,
        cost => 1000,
        period => 1,
        reference_date => '2017-01-15 00:00:00'
    ), '3.15', 'calc_period_by_total: 3.5 months from mid-January'
);

done_testing();
