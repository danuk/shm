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

my $payload = $t->payload;
is( exists $payload->{headers}, 1, 'Check payload' );

done_testing();
