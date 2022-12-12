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

my $event = get_service('events');
my @events;

subtest 'Check exists events' => sub {
    @events = $event->get_events(
        kind => 'UserService',
        name => 'create',
        category => 'test',

    );

    is( scalar @events, 0 );
};

subtest 'Add two new events' => sub {
    $event->add(
        title => 'event 1',
        name => 'create',
        server_gid => 1,
        settings => {
            category => 'test',
        },
    );

    $event->add(
        title => 'event 2',
        name => 'create',
        server_gid => 1,
        settings => {
            category => 'test',
        },
    );

    $event->add(
        title => 'event 3 (always match)',
        name => 'create',
        server_gid => 1,
        settings => {
            category => '%',
        },
    );

    $event->add(
        title => 'event 4 (always match but another event)',
        name => 'delete',
        server_gid => 1,
        settings => {
            category => '%',
        },
    );

    @events = $event->get_events(
        kind => 'UserService',
        name => 'create',
        category => 'test',
    );

    is( scalar @events, 3 );
};

subtest 'Check events for new service' => sub {
    my $service_id = get_service('service')->add(
        name => 'test service',
        cost => 0,
        category => 'test',
    )->id;

    my $us = get_service('us')->add(
        service_id => $service_id,
    );

    is( $us->get_service_id, $service_id );
    is( scalar @{ $us->commands_by_event('create') }, 3 );
    is ( $us->has_spool_command, 0 );
    is ( $us->event( 'create' ), SUCCESS );
    is ( $us->has_spool_command, 3 );
};

done_testing();

