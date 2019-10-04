#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service );
use Data::Dumper;

SHM->new( skip_check_auth => 1 );

while ( get_service('spool')->process_one() ) {};

exit 0;
