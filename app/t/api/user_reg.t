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

my %test = shm_test_api(
    login => 'admin',
    password => 'admin',
    url => 'v1/admin/user?user_id='. $ret{json}->{data}->[0]->{user_id},
    method => 'DELETE',
);

is $test{success}, 1, 'Check user delete status';

done_testing();

exit 0;

