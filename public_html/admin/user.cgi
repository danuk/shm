#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
    start_of_month
    http_limit
    http_content_range
    now
);

our %in = parse_args();

unless ( $in{user_id} ) {
    print_header( status => 400 );
    exit 0;
}

my $res = $user->id( $in{user_id} );

unless ( $res ) {
    print_header( status => 404 );
    exit 0;
}

print_json( scalar $res->get );

exit 0;

