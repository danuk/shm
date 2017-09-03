use v5.14;
use warnings;
use utf8;

use Test::More;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );
my $obj = get_service('USObject', _id => 99 );

get_service('spool')->add(
    server_id => 1,
    category => 'test',
    user_service_id => 16,
    event => 'create',
    cmd => 'test create',
);

get_service('spool')->add(
    server_id => 1,
    category => 'dns',
    user_service_id => 16,
    event => 'create',
    cmd => 'test create',
);

get_service('spool')->add(
    server_id => 162,
    category => 'dns',
    user_service_id => 16,
    event => 'create',
    cmd => 'test create',
);

my $spool = get_service('spool');

while ( $spool->process_one ){};

#say Dumper $spool->list;
#exit;

my ( $task1, $task2, $task3 ) = $spool->list;

is $task1->{status}, 1, 'Check status task #1';
is $task2->{status}, 1, 'Check status task #2';
is $task3->{status}, 3, 'Check status task #3';

done_testing();
