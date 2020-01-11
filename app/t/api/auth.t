use v5.14;
use utf8;

use Test::More;
use Test::Deep;

use Core::Utils qw/decode_json/;

subtest 'Check auth with incorrect credentials' => sub {
    my $ret = qx(
        curl -s \\
        -H "Content-Type: application/json" \\
        -H "login: foo" \\
        -H "password: bar" \\
        -X GET \\
        http://shm.local/admin/pay.cgi
    );

    my $json_ret = decode_json( $ret );

    cmp_deeply( $json_ret, {
        msg => 'Incorrect login or password',
        status => 401,
    });
};

subtest 'Check auth with correct credentials' => sub {
    my $ret = qx(
        curl -s \\
        -H "Content-Type: application/json" \\
        -H "login: admin" \\
        -H "password: admin" \\
        -X GET \\
        http://shm.local/admin/pay.cgi
    );

    my $json_ret = decode_json( $ret );

    is( scalar @{ $json_ret }, 2 );
};

done_testing();
