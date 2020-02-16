#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw/to_json/;

$| = 1;

SHM->new( skip_check_auth => 1 );

my $spool = get_service('spool');
my ($status, $task, $info );

say "SHM spool started at: " . localtime;

for (;;) {
    do {
        ($status, $task, $info ) = $spool->process_one();

        if ( defined $task ) {
            $task->{status} //= $status;
            say to_json( $task, {pretty => 1} );
        }
    } while defined $task;

    $spool->{spool} = undef;
    sleep 2;
}

exit 0;
