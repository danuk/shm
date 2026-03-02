#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service unregister_all );
use Try::Tiny;
use Core::Const;
use Core::Utils qw(
    encode_json_perl
);
no warnings;

POSIX::setgid(33); # www-data
POSIX::setuid(33); # www-data

$| = 1;

my $user = SHM->new( user_id => 1 );
$user->dbh->{RaiseError} = 1;
# Core::System::ServiceManager::setup();

my $task;

say "SHM spool started at: " . localtime;

my $spool = get_service('spool');

for (;;) {
    my $task_exists = 0;
    do {
        try {
            ( $task ) = $spool->process_one();

            if ( ref $task ) {
                $task_exists = 1;
                say encode_json_perl( $task );
            }
        } catch {
            my $error = $_;
            warn $error;

            if ( ref $task ) {
                $task->retry_task(
                    status => TASK_FAIL,
                    response => { error => $error },
                );
            }
        };
        $user->commit;
        unregister_all();
    } while defined $task;

    sleep 1 unless $task_exists;
}

exit 0;
