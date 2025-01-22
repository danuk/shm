#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service unregister_all );
use JSON;
use Try::Tiny;
use Core::Const;
no warnings;

my $json = JSON->new->canonical( 1 );

$| = 1;

my $user = SHM->new( user_id => 1 );
$user->dbh->{RaiseError} = 1;

my ( $status, $task, $info );

say "SHM spool started at: " . localtime;

for (;;) {
    do {
        try {
            my $spool = get_service('spool');
            ( $status, $task, $info ) = $spool->process_one();

            if ( defined $task ) {
                $task->{status} //= $status;
                say $json->encode( $task );
            }
        } catch {
            my $error = $_;
            warn $error;

            if ( defined $task ) {
                $task->finish_task(
                    status => TASK_STUCK,
                    response => { error => $error },
                );
            }
        };
        $user->commit;
        unregister_all();
    } while defined $task;

    sleep 1;
}

exit 0;
