use v5.14;
use utf8;

use Core::Utils qw/shm_test_api/;

use Test::More;

use SHM;
my $user = SHM->new( user_id => 40094 );
my $balance_before = $user->balance;

my $login = sprintf( "login-%d", time );

my %ret = shm_test_api(
    url => 'v1/user',
    method => 'PUT',
    data => {
        login => $login,
        password => '123',
    },
);

is( $ret{json}->{data}->[0]->{login}, $login, 'Register new user');

done_testing();

exit 0;

