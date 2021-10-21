use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

my $ret = $user->reg(
    login => 'shm@mail.ru',
    password => '12345678',
);

is( $ret->{login}, 'shm@mail.ru');

done_testing();
