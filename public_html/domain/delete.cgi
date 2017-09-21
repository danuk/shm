#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
);

our %in = parse_args();

sub usage {
    print_json( {status => 400, msg => "`domain_id` required"} );
    exit 1;
}

usage unless ( $in{domain_id} );

my $domain = get_service('domain', _id => $in{domain_id} );

my $ret = $domain->delete();

unless ( $ret ) {
    print_json( {status => 404, msg => "domain not exists"} );
    exit 1;
};

print_json( { msg => 'successful', result => 0 } );

exit 0;
