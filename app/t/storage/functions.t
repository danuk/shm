use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

my $storage = $user->srv('storage');

$storage->add(
    name => 'test',
    data => { foo => 1 },
    settings => {
        json => 1,
    },
);

my $data = $storage->read( name => 'test' );
is( $data->{foo}, 1 );

$storage->replace(
    name => 'test',
    data => { foo => 2 },
    settings => {
        json => 1,
    },
);

my $data = $storage->read( name => 'test' );
is( $data->{foo}, 2 );

cmp_deeply( scalar $storage->id('test')->get, {
    'data' => {"foo" => 2},
    'created' => ignore(),
    'user_service_id' => undef,
    'user_id' => 40092,
    'name' => 'test',
    'settings' => {
        'json' => 1
    }
});

done_testing();
