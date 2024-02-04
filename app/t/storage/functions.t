use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

my $storage = get_service('storage');

my @list = $storage->list;
is( scalar @list, 0);

$storage->add(
    name => 'test',
    data => { foo => 1 },
    settings => {
        json => 1,
    },
);

my $data = $storage->read( name => 'test' );
is( $data->{foo}, 1 );

my @list = $storage->list;
is( scalar @list, 1);

done_testing();
