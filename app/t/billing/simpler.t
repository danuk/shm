use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Billing::Simpler qw(
    calc_end_date_by_months
    calc_total_by_date_range
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
is( calc_end_date_by_months('2017-01-01 00:00:00', '0.01'), '2017-01-01 23:59:59', 'Test calc_end_date_by_months 13');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-01 23:59:59',
        cost            => '900',
    ),
    {
        total => '30.00',
        months => '0.01',
    }
,'calc_total_by_date_range (one day without one second)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-02 00:00:00',
        cost            => '900',
    ),
    {
        total => '30.00',
        months => '0.01',
    }
,'calc_total_by_date_range (one day)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-01 08:00:00',
        cost            => '900',
    ),
    {
        total => '10.00',
        months => '0.00',
    }
,'calc_total_by_date_range (third part of day)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-30 23:59:59',
        cost            => '1000',
    ),
    {
        total => '1000.00',
        months => '1.00',
    }
,'calc_total_by_date_range (30 days)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-03-01 23:59:59',
        cost            => '1000',
    ),
    {
        total => '2000.00',
        months => '2.00',
    }
,'calc_total_by_date_range (60 days)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-02-09 12:33:00',
        cost            => '1000',
    ),
    {
        total => '1000.00',
        months => '1.00',
    }
,'calc_total_by_date_range (30 days in other months)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-02-10 12:33:00',
        cost            => '1000',
    ),
    {
        total => '1033.33',
        months => '1.01',
    }
,'calc_total_by_date_range (31 day)');

cmp_deeply( calc_total_by_date_range(
        withdraw_date   => '2017-10-31 00:00:00',
        end_date        => '2018-02-01 23:59:59',
        cost            => '3100',
    ),
    {
        total => '9713.33',
        months => '3.04',
    }
,'calc_total_by_date_range (jump to next year)');

done_testing();
