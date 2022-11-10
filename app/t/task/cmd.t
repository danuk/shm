use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

subtest 'Check task with not exists server' => sub {
    my $t = get_service('Task')->res({
        event => {
            kind => 'user_service',
            name => 'update',
            settings => {
                category => 'dns',
                cmd => 'dns update',
            },
        },
        settings => {
            user_service_id => 16,
            server_id => 123,
        },
    });

    my $payload = $t->payload;
    is( exists $payload->{headers}, 1, 'Check payload' );

    is( $t->settings->{server_id}, 123 );
    is( $t->server_id, 123 );
    is( $t->event_settings->{category}, 'dns' );
    is( $t->server, undef );
    is( $t->server( transport => 'ssh' ), undef );
};

subtest 'Check task with exists server1' => sub {
    my $t = get_service('Task')->res({
            event => {
                kind => 'user_service',
                name => 'update',
                settings => {
                    category => 'dns',
                    cmd => 'dns update',
                },
            },
            settings => {
                user_service_id => 16,
                server_id => 1,
            },
        });

    is( $t->settings->{server_id}, 1 );
    is( $t->server_id, 1 );
    is( $t->event_settings->{category}, 'dns' );
    is( $t->server->id, 1 );
    is( $t->server( transport => 'ssh' )->id, 1 );
};

subtest 'Check task with exists server2' => sub {
    my $t = get_service('Task')->res({
            event => {
                kind => 'user_service',
                name => 'update',
                settings => {
                    category => 'dns',
                    cmd => 'dns update',
                },
            },
            settings => {
                user_service_id => 16,
                server_id => 2,
            },
        });

    is( $t->settings->{server_id}, 2 );
    is( $t->server_id, 2 );
    is( $t->event_settings->{category}, 'dns' );
    is( $t->server->id, 2 );
    is( $t->server( transport => 'ssh' )->id, 2 );
};

subtest 'Check task without server' => sub {
    my $t = get_service('Task')->res({
        event => {
            kind => 'user_service',
            name => 'update',
            settings => {
                category => 'dns',
                cmd => 'dns update',
            },
        },
        settings => {
            user_service_id => 16,
        },
    });

    is( $t->settings->{server_id}, undef );
    is( $t->server_id, undef );
    is( $t->event_settings->{category}, 'dns' );
    is( $t->server( transport => 'ssh' )->id, 1 );
};

done_testing();
