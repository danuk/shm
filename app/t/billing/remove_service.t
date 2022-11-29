use strict;
use warnings;

use v5.14;

use Test::More;
use Data::Dumper;
use SHM;
use Core::System::ServiceManager qw( get_service );
use Core::Const;

$ENV{SHM_TEST} = 1;

SHM->new( user_id => 40092 );
my $spool = get_service('spool');

my $t = get_service('Transport::Ssh');
no warnings 'once';
no warnings qw(redefine);
*Core::Transport::Ssh::exec = sub {
    my $self = shift;
    my %args = @_;

    return SUCCESS, {
        server => {
            id => $args{server_id},
            host => $args{host},
            port => $args{port},
            key_id => $args{key_id},
        },
        cmd => $args{cmd},
        ret_code => 0,
        pipeline_id => $args{pipeline_id},
    };
};

subtest 'Test1: Parent have EVENT' => sub {
    get_service('events')->add(
        name => EVENT_REMOVE,
        title => 'test event',
        server_gid => 1,
        settings => {
            category => 'test1',
        },
    );

    my $service_id = get_service('service')->add(
        name => 'test service',
        category => 'test1',
        cost => 0,
    )->id;


    my $sub_service_id = get_service('service')->add(
        name => 'test sub service',
        category => 'some_category',
        cost => 0,
    )->id;

    my $us = get_service('us')->add(
        service_id => $service_id,
        status => 'BLOCK',
    );

    is( $us->has_children, 0 );

    my $us_sub1 = get_service('us')->add(
        service_id => $sub_service_id,
        status => 'BLOCK',
        parent => $us->id,
    );

    is( $us->has_children, 1 );
    is( $us->is_commands_by_event( EVENT_REMOVE ), 1 );
    is( $us->has_spool_command, 0 );
    is( $us_sub1->is_commands_by_event( EVENT_REMOVE ), 0 );
    is( $us_sub1->has_spool_command, 0 );

    $us->touch( EVENT_REMOVE );
    is( $us->has_spool_command, 1 );
    is( $us_sub1->has_spool_command, 0 );
    is( $us->status, 'PROGRESS');
    is( $us_sub1->status, 'REMOVED');

    $spool->process_all();
    is( $us->status, 'REMOVED');
    is( $us_sub1->status, 'REMOVED');
};

subtest 'Test2: CHILD have EVENT' => sub {
    get_service('events')->add(
        name => EVENT_REMOVE,
        title => 'test event',
        server_gid => 1,
        settings => {
            category => 'test2',
        },
    );

    my $service_id = get_service('service')->add(
        name => 'test service',
        category => 'some_category',
        cost => 0,
    )->id;

    my $sub_service_id = get_service('service')->add(
        name => 'test sub service',
        category => 'test2',
        cost => 0,
    )->id;

    my $us = get_service('us')->add(
        service_id => $service_id,
        status => 'BLOCK',
    );

    is( $us->has_children, 0 );

    my $us_sub1 = get_service('us')->add(
        service_id => $sub_service_id,
        status => 'BLOCK',
        parent => $us->id,
    );

    is( $us->has_children, 1 );
    is( $us->is_commands_by_event( EVENT_REMOVE ), 0 );
    is( $us->has_spool_command, 0 );
    is( $us_sub1->has_spool_command, 0 );
    is( $us_sub1->is_commands_by_event( EVENT_REMOVE ), 1 );

    $us->touch( EVENT_REMOVE );
    is( $us->has_spool_command, 0 );
    is( $us_sub1->has_spool_command, 1 );
    is( $us->status, 'PROGRESS');
    is( $us_sub1->status, 'PROGRESS');

    $spool->process_all();
    is( $us->status, 'REMOVED');
    is( $us_sub1->status, 'REMOVED');
};

subtest 'Test3: PARENT have EVENT, CHILD have EVENT' => sub {
    get_service('events')->add(
        name => EVENT_REMOVE,
        title => 'test event',
        server_gid => 1,
        settings => {
            category => 'test3',
        },
    );

    my $service_id = get_service('service')->add(
        name => 'test service',
        category => 'test3',
        cost => 0,
    )->id;

    my $sub_service_id = get_service('service')->add(
        name => 'test sub service',
        category => 'test3',
        cost => 0,
    )->id;

    my $us = get_service('us')->add(
        service_id => $service_id,
        status => 'BLOCK',
    );

    is( $us->has_children, 0 );

    my $us_sub1 = get_service('us')->add(
        service_id => $sub_service_id,
        status => 'BLOCK',
        parent => $us->id,
    );

    is( $us->has_children, 1 );
    is( $us->is_commands_by_event( EVENT_REMOVE ), 1 );
    is( $us_sub1->is_commands_by_event( EVENT_REMOVE ), 1 );
    is( $us->has_spool_command, 0 );
    is( $us_sub1->has_spool_command, 0 );

    $us->touch( EVENT_REMOVE );
    is( $us->has_spool_command, 0 );
    is( $us_sub1->has_spool_command, 1 );
    is( $us->status, 'PROGRESS');
    is( $us_sub1->status, 'PROGRESS');

    $spool->process_all();
    is( $us->has_spool_command, 1 );
    is( $us_sub1->has_spool_command, 0 );
    is( $us->status, 'PROGRESS');
    is( $us_sub1->status, 'REMOVED');

    $spool->process_all();
    is( $us->has_spool_command, 0 );
    is( $us_sub1->has_spool_command, 0 );
    is( $us->status, 'REMOVED');
    is( $us_sub1->status, 'REMOVED');
};

subtest 'Test4: PARENT have EVENT, CHILD1 have EVENT, CHILD2 have not EVENT' => sub {
    get_service('events')->add(
        name => EVENT_REMOVE,
        title => 'test event',
        server_gid => 1,
        settings => {
            category => 'test4',
        },
    );

    my $service_id = get_service('service')->add(
        name => 'test service',
        category => 'test4',
        cost => 0,
    )->id;

    my $sub_service_id = get_service('service')->add(
        name => 'test sub service',
        category => 'test4',
        cost => 0,
    )->id;

    my $us = get_service('us')->add(
        service_id => $service_id,
        status => 'BLOCK',
    );

    is( $us->has_children, 0 );

    my $us_sub1 = get_service('us')->add(
        service_id => $sub_service_id,
        status => 'BLOCK',
        parent => $us->id,
    );

    my $us_sub2 = get_service('us')->add(
        service_id => 11,
        status => 'BLOCK',
        parent => $us->id,
    );

    is( $us->has_children, 2 );
    is( $us->is_commands_by_event( EVENT_REMOVE ), 1 );
    is( $us_sub1->is_commands_by_event( EVENT_REMOVE ), 1 );
    is( $us_sub2->is_commands_by_event( EVENT_REMOVE ), 0 );
    is( $us->has_spool_command, 0 );
    is( $us_sub1->has_spool_command, 0 );
    is( $us_sub2->has_spool_command, 0 );

    $us->touch( EVENT_REMOVE );
    is( $us->has_spool_command, 0 );
    is( $us_sub1->has_spool_command, 1 );
    is( $us_sub2->has_spool_command, 0 );
    is( $us->status, 'PROGRESS');
    is( $us_sub1->status, 'PROGRESS');
    is( $us_sub2->status, 'REMOVED');

    $spool->process_all();
    is( $us->has_spool_command, 1 );
    is( $us_sub1->has_spool_command, 0 );
    is( $us_sub2->has_spool_command, 0 );
    is( $us->status, 'PROGRESS');
    is( $us_sub1->status, 'REMOVED');
    is( $us_sub2->status, 'REMOVED');

    $spool->process_all();
    is( $us->has_spool_command, 0 );
    is( $us_sub1->has_spool_command, 0 );
    is( $us_sub2->has_spool_command, 0 );
    is( $us->status, 'REMOVED');
    is( $us_sub1->status, 'REMOVED');
    is( $us_sub2->status, 'REMOVED');
};

done_testing();

