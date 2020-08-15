#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
);

our %in = parse_args();

unless ( $in{id} ) {
    print_header( status => 400 );
    print_json( { error => "id not present" } );
    exit 0;
}

my $console = get_service( 'Console', _id => $in{id} );

my $log = $console->chunk(
    offset => $in{offset} || 1,
);

print_header(
    'type' => 'text/plain',
    'Access-Control-Expose-Headers' => 'x-console-eof',
    'x-console-eof' => $console->eof,
);

print $log;

exit 0;

