use v5.14;
use warnings;
use utf8;

use Test::More;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::Const;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $task1 = get_service('spool')->add(
    event => {
        kind => 'user_service',
        name => 'update',
        params => {
            category => 'dns',
            cmd => 'dns update',
        },
    },
    params => {
        user_service_id => 16,
        server_id => 1,
    },
);

my $task2 = get_service('spool')->add(
    event => {
        kind => 'user_service',
        name => 'update',
        params => {
            category => 'dns',
            cmd => 'dns update',
        },
    },
    params => {
        user_service_id => 16,
        server_id => 162,
    },
);

my $task3 = get_service('task')->res({
    event => {
        kind => 'user_service',
        name => 'update',
        params => {
            category => 'dns',
            cmd => 'dns update',
        },
    },
    params => {
        user_service_id => 16,
        server_id => 1,
    },
})->make_task;

is( $task3->{response}->{ret_code}, 0, 'Check make_task for category `test`' );

my $spool = get_service('spool');

while ( $spool->process_one ){};

is( ($spool->list)[0]->{status}, TASK_STUCK, "Server: 162 not exists" );

my @ret = get_service('SpoolHistory')->list(
    where => { spool_id => { -in => [ $task1, $task2 ] } },
    order => [ spool_id => 'ASC' ],
);

is( $ret[0]->{status}, TASK_SUCCESS, 'Send test message for test services' );

my @list = $spool->list( where => { status => { '!=', TASK_STUCK } } );
is ( @list, 0, 'Check for empty spool' );

done_testing();
