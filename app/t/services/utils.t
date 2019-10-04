use v5.14;

use Test::More;
use Data::Dumper;
use Core::Utils;

is( Core::Utils::days_in_months('2016-02'), 29, 'Test days_in_months 1' );
is( Core::Utils::days_in_months('2017-02'), 28, 'Test days_in_months 2' );
is( Core::Utils::days_in_months('2017-02-05 10:12:43'), 28, 'Test days_in_months 3' );

is_deeply( scalar Core::Utils::parse_date('2017-02-05 10:12:43'), {
    year => 2017,
    month => 2,
    day => 5,
    hour => 10,
    min => 12,
    sec => 43,
    tz => undef,
}, 'Test parse_date' );

is( Core::Utils::start_of_month('2017-01-15 15:14:13'),'2017-01-01 00:00:00','Test start start_of_month');
is( Core::Utils::start_of_month('2017-01-15'),'2017-01-01 00:00:00','Test start_of_month');
is( Core::Utils::end_of_month('2017-01-15'),'2017-01-31 23:59:59','Test end_of_month');
is( Core::Utils::end_of_month('2017-02-13'),'2017-02-28 23:59:59','Test end_of_month');

done_testing();
