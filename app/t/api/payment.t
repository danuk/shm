use v5.14;
use utf8;

use Test::More;
use Test::Deep;

use Core::Utils qw/
    decode_json
/;

my $ret = qx(
    curl -s \\
    -H "Content-Type: application/json" \\
    -H "test: 1" \\
    -H "login: admin" \\
    -H "password: admin" \\
    -X PUT \\
    -d '{"user_id":40092,"pay_system_id":"test","money":123.45,"comment":"Test payment #4"}' \\
    http://api/shm/v1/admin/user/payment
);

my $json_ret = decode_json( $ret );

cmp_deeply( $json_ret->{data}->[0], {
    id => ignore(),
    user_id => 40092,
    date => ignore(),
    pay_system_id => 'test',
    money => 123.45,
    comment => {
        comment => 'Test payment #4',
    },
}, 'Test API');

done_testing();
