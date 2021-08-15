use strict;
use warnings;

use v5.14;

use Test::More;
use Data::Dumper;
use SHM;
use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;

SHM->new( user_id => 40092 );

get_service('events')->add(
    name => 'test',
    title => 'test event',
    server_gid => 1,
    settings => {
        category => 'test',
    },
);

my $service_id = get_service('service')->add(
    name => 'test service',
    category => 'test',
    cost => 0,
)->id;


my $sub_service_id = get_service('service')->add(
    name => 'test sub service',
    category => 'some_category',
    cost => 0,
)->id;

my $us = get_service('us')->add(
    service_id => $service_id,
    status => 'ACTIVE',
);

is( $us->has_children, 0 );

my $sub_us = get_service('us')->add(
    service_id => $sub_service_id,
    status => 'BLOCK',
    parent => $us->id,
);

is( $us->has_children, 1 );
is( $us->has_spool_command, 0 );

$us->make_commands_by_event('test');
is( $us->has_spool_command, 1 );

$sub_us->delete();
is( $sub_us->status, 'REMOVED');
is( $us->status, 'PROGRESS');

done_testing();
