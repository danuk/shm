use v5.14;

use Test::More;
use Data::Dumper;
use Core::Billing;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $us = SHM->new( user_id => 40092 );

is( Core::Billing::calc_end_date_by_months('2017-01-01 00:00:00', 1), '2017-01-31 23:59:59', 'Test calc_end_date_by_months 1');
is( Core::Billing::calc_end_date_by_months('2017-07-01 00:00:00', 1), '2017-07-31 23:59:59', 'Test calc_end_date_by_months 2');
is( Core::Billing::calc_end_date_by_months('2017-07-02 00:00:00', 1), '2017-08-01 23:59:59', 'Test calc_end_date_by_months 3');

is( Core::Billing::calc_end_date_by_months('2017-02-01 00:00:00', 1), '2017-02-28 23:59:59', 'Test calc_end_date_by_months 4');
is( Core::Billing::calc_end_date_by_months('2017-02-01 00:00:01', 1), '2017-03-01 00:00:00', 'Test calc_end_date_by_months 5');

is( Core::Billing::calc_end_date_by_months('2017-01-10 12:33:00', 1), '2017-02-09 14:25:55', 'Test calc_end_date_by_months 6');

is( Core::Billing::calc_end_date_by_months('2017-01-01 00:00:00', 2), '2017-02-28 23:59:59', 'Test calc_end_date_by_months 6');
is( Core::Billing::calc_end_date_by_months('2017-01-01 00:00:00', 3), '2017-03-31 23:59:59', 'Test calc_end_date_by_months 7');

is( Core::Billing::calc_end_date_by_months('2017-02-05 00:00:00', 1), '2017-03-05 10:17:07', 'Test calc_end_date_by_months 8');

is( Core::Billing::calc_end_date_by_months('2017-02-27 00:00:00', 1), '2017-03-29 18:51:24', 'Test calc_end_date_by_months 9');
is( Core::Billing::calc_end_date_by_months('2017-03-29 18:51:25', 1), '2017-04-28 20:34:15', 'Test calc_end_date_by_months 10');
is( Core::Billing::calc_end_date_by_months('2017-04-28 20:34:16', 1), '2017-05-29 18:51:23', 'Test calc_end_date_by_months 11');

is( Core::Billing::calc_end_date_by_months('2017-01-01 00:00:00', '0.1'), '2017-01-10 23:59:59', 'Test calc_end_date_by_months 12');
is( Core::Billing::calc_end_date_by_months('2017-01-01 00:00:00', '0.01'), '2017-01-01 23:59:59', 'Test calc_end_date_by_months 13');

is_deeply( Core::Billing::calc_month_cost( from_date => '2017-04-01 00:00:00', cost => '3000' ), {
    start => '2017-04-01 00:00:00',
    stop => '2017-04-30 23:59:59',
    total => '3000.00',
},'calc_month_cost: from_date (1 month)');

is_deeply( Core::Billing::calc_month_cost( from_date => '2017-04-30 23:59:59', cost => '3000' ), {
    start => '2017-04-30 23:59:59',
    stop => '2017-04-30 23:59:59',
    total => '0.00',
},'calc_month_cost: from_date (0 day)');

is_deeply( Core::Billing::calc_month_cost( from_date => '2017-04-30 00:00:00', cost => '3000' ), {
    start => '2017-04-30 00:00:00',
    stop => '2017-04-30 23:59:59',
    total => '100.00',
},'calc_month_cost: from_date (1 day)');

is_deeply( Core::Billing::calc_month_cost( to_date => '2017-04-30 23:59:59', cost => '3000' ), {
    start => '2017-04-01 00:00:00',
    stop => '2017-04-30 23:59:59',
    total => '3000.00',
},'calc_month_cost: to_date (0 day)');

is_deeply( Core::Billing::calc_month_cost( to_date => '2017-04-09 23:59:59', cost => '3000' ), {
    start => '2017-04-01 00:00:00',
    stop => '2017-04-09 23:59:59',
    total => '900.00',
},'calc_month_cost: to_date (9 day)');

is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-31 23:59:59',
        cost            => '1000',
), '1000.00','calc_total_by_date_range');

is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-02-28 23:59:59',
        cost            => '1000',
), '2000.00','calc_total_by_date_range');

is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-04-30 23:59:59',
        cost            => '1000',
), '4000.00','calc_total_by_date_range');

is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-04-10 12:33:00',
        cost            => '1000',
), '3010.24','calc_total_by_date_range');

is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-05-10 12:33:00',
        cost            => '1000',
), '4000.00','calc_total_by_date_range');

# Проверяем, что между двумя датами, различающихся на один месяц,
# списание не месячное (более 1000 руб.). Это правильно, т.к. в месяцах разное кол-во дней
is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-02-10 12:33:00',
        cost            => '1000',
), '1032.91','calc_total_by_date_range');

# Ранее, к дате списания прибавил месяц, и получил дату окончания
# Проверяем, что между этими двумя датами списание равно месячному.
# Эта ф-ия является обратной к calc_end_date_by_months
is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-10 12:33:00',
        end_date        => '2017-02-09 14:25:55',
        cost            => '1000',
), '1000.00','calc_total_by_date_range');

# Вычисляем стоимость короткого периода (для двух дней)
is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-01 00:00:00',
        end_date        => '2017-01-02 23:59:59',
        cost            => '3100',
), '200.00','calc_total_by_date_range (2 days on start month)');

# Вычисляем стоимость короткого периода (для двух дней)
is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-10 00:00:00',
        end_date        => '2017-01-11 23:59:59',
        cost            => '3100',
), '200.00','calc_total_by_date_range (2 days in middle)');

# Вычисляем стоимость короткого периода (для двух дней с переходом месяца)
is( Core::Billing::calc_total_by_date_range(
        withdraw_date   => '2017-01-31 00:00:00',
        end_date        => '2017-02-01 23:59:59',
        cost            => '3100',
), '210.71','calc_total_by_date_range (2 days with jump to next month)');

is( Core::Billing::get_service_discount( service_id => 1 ), 0, 'get service discount percent' );
is( Core::Billing::get_service_discount( months => 2, service_id => 1 ), 0, 'get service discount percent' );
is( Core::Billing::get_service_discount( months => 3, service_id => 1 ), 10, 'get service discount percent' );

is( Core::Billing::get_service_discount( service_id => 11 ), 0, 'get service discount percent for domain' );
is( Core::Billing::get_service_discount( months => 12, service_id => 11 ), 0, 'get service discount percent for domain' );
is( Core::Billing::get_service_discount( months => 24, service_id => 11 ), 0, 'get service discount percent for domain' );
is( Core::Billing::get_service_discount( months => 11, service_id => 11 ), 0, 'get service discount percent for domain' );

get_service('user')->set( discount => 13 );
is( Core::Billing::get_service_discount( service_id => 1 ), 13, 'get service discount percent' );

done_testing();
