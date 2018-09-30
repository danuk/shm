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

my $user_id = $in{user_id};

if ( $ENV{REQUEST_METHOD} eq 'PUT' ) {
    unless ( $user_id = get_service('user')->reg( %in ) ) {
        my $report = get_service('report')->errors;
        print_json( { status => 400, msg => $report } );
        exit 0;
    }
} else {
    unless ( $user_id ) {
        print_header( status => 400 );
        exit 0;
    }
}

my $res = $user->id( $user_id );

unless ( $res ) {
    print_header( status => 404 );
    exit 0;
}

print_json( scalar $res->get );

exit 0;

