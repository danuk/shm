#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service );
use Data::Dumper;

SHM->new( skip_check_auth => 1 );

my $spool = get_service('spool');

for (;;) {
    while ( $spool->process_one() ) {};
    $spool->{spool} = undef;
    sleep 2;
}

exit 0;
