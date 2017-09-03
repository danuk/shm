#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $cli = SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    start_of_month
    http_limit
    http_content_range
    now
    parse_args
);

my %in = parse_args();

my @res = get_service('pay')->list_for_api(
    start => $in{start} || start_of_month,
    stop => $in{stop} || now,
    limit => { http_limit },
);

my $numRows = $cli->user->found_rows;

print_header( http_content_range( http_limit, count => $numRows ) );
print_json( \@res );

exit 0;
