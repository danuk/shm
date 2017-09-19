#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
);

our %in = parse_args();

my $domain = get_service('domain');

my $domain_id = $domain->add(
    type => 0,
    domain => $in{domain},
);

print_json( { status => $domain_id ? 'ok' : 'error' } );

exit 0;
