use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Utils qw/shm_test_api/;

my %user = (
    login => 'admin',
    password => 'admin',
);

my %ret = shm_test_api(
    url => '/v1/admin/user/service?filter={"user_id":"40092"}',
    method => 'GET',
    %user,
);

is $ret{json}->{items}, 4, 'Check items field';
is scalar @{ $ret{json}->{data} }, 4, 'Check count items in data';

done_testing();

exit 0;

