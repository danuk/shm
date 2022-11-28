use v5.14;
use utf8;

use Core::Utils qw/shm_test_api/;

use Test::More;
use Test::Deep;

use SHM;
my $user = SHM->new( user_id => 40094 );
my $balance_before = $user->balance;

my $payment = 123;
my %ret = shm_test_api(
    url => '/v1/admin/user/payment',
    login => 'admin',
    password => 'admin',
    method => 'PUT',
    data => {
        user_id => 40094,
        money => $payment,
        pay_system_id => 'manual',
    },
);

cmp_deeply( $ret{json}->{data}->[0], {
    id => ignore(),
    user_id => 40094,
    money => 123,
    pay_system_id => 'manual',
    date => ignore(),
    comment => undef
}, 'Test /v1/admin/user/payment');

$user->commit;
$user->reload();

is $user->balance, $balance_before + $payment, 'Check balance after payment';

done_testing();

exit 0;

