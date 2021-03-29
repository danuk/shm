use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $us = SHM->new( user_id => 40092 );

my $user = get_service('user');

my $object = $user->reg(
    login => 'shm@mail.ru',
    password => '12345678',
);

my %user = $object->get();

is( $user{login}, 'shm@mail.ru');

done_testing();
