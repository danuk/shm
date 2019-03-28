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

my $t = get_service('Task')->res({
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
});

my @cmd = $t->make_cmd_args( $t->cmd );

cmp_deeply( \@cmd, [
    'dns',
    'update',
], 'Check parsing command #1' );

my $payload = $t->payload;
is( exists $payload->{headers}, 1, 'Check payload' );

@cmd = $t->make_cmd_args('service create "{{ id }}" "{{us.expired}}" {{domain}},www.{{domain}}');

cmp_deeply( \@cmd, [
    'service',
    'create',
    '16',
    '2017-09-22 14:51:26',
    'danuk.ru,www.danuk.ru',
], 'Check parsing command #2' );



done_testing();
