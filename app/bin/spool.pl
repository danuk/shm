#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service unregister_all );
use JSON;
no warnings;

my $json = JSON->new->canonical( 1 );

$| = 1;

my $user = SHM->new( skip_check_auth => 1 );

my $spool = get_service('spool');
my ($status, $task, $info );

say "SHM spool started at: " . localtime;

for (;;) {
    do {
        ($status, $task, $info ) = $spool->process_one();
        $user->commit();

        if ( defined $task ) {
            $task->{status} //= $status;
            say $json->encode( $task );
        }
    } while defined $task;

    $spool->{spool} = undef;
    unregister_all();
    sleep 2;
}

exit 0;
