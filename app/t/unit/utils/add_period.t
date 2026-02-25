#!/usr/bin/perl
use v5.14;
use utf8;
use Test::More tests => 22;
use lib '/app/lib';

use Core::Utils qw(add_period);

my $date = '2025-01-15 10:30:00';

# Test adding days
is(add_period($date, '1d'), '2025-01-16 10:30:00', 'Add 1 day');
is(add_period($date, '5d'), '2025-01-20 10:30:00', 'Add 5 days');
is(add_period($date, '30d'), '2025-02-14 10:30:00', 'Add 30 days');

# Test adding months
is(add_period($date, '1m'), '2025-02-15 10:30:00', 'Add 1 month');
is(add_period($date, '12m'), '2026-01-15 10:30:00', 'Add 12 months');

# Test adding years
is(add_period($date, '1y'), '2026-01-15 10:30:00', 'Add 1 year');
is(add_period($date, '2y'), '2027-01-15 10:30:00', 'Add 2 years');

# Test adding hours
is(add_period($date, '1H'), '2025-01-15 11:30:00', 'Add 1 hour');
is(add_period($date, '5H'), '2025-01-15 15:30:00', 'Add 5 hours');
is(add_period($date, '12H'), '2025-01-15 22:30:00', 'Add 12 hours');
is(add_period($date, '24H'), '2025-01-16 10:30:00', 'Add 24 hours (1 day)');

# Test adding minutes
is(add_period($date, '1M'), '2025-01-15 10:31:00', 'Add 1 minute');
is(add_period($date, '30M'), '2025-01-15 11:00:00', 'Add 30 minutes');
is(add_period($date, '60M'), '2025-01-15 11:30:00', 'Add 60 minutes (1 hour)');

# Test month boundary (Jan 31 + 1 month = Mar 3, due to Date::Calc behavior)
my $date_jan31 = '2025-01-31 12:00:00';
is(add_period($date_jan31, '1m'), '2025-03-03 12:00:00', 'Month boundary: Jan 31 + 1 month = Mar 3');

# Test year boundary (Dec 31 + 1 day)
my $date_dec31 = '2025-12-31 23:59:59';
is(add_period($date_dec31, '1d'), '2026-01-01 23:59:59', 'Year boundary: Dec 31 + 1 day');

# Test invalid period formats (should return original date)
is(add_period($date, 'invalid'), $date, 'Invalid period format returns original date');
is(add_period($date, '5'), $date, 'Period with no unit returns original date');
is(add_period($date, '5x'), $date, 'Period with invalid unit returns original date');

# Test missing arguments (should return undef)
is(add_period(undef, '1d'), undef, 'No date argument returns undef');
is(add_period($date, undef), undef, 'No period argument returns undef');

# Test edge case: zero period
is(add_period($date, '0m'), $date, '0 months returns original date');

done_testing();
