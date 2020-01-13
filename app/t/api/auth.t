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

my $session_id;

subtest 'Check common auth (auth.cgi)' => sub {
    my $ret = qx(
        curl -s \\
        -H "Content-Type: application/x-www-form-urlencoded" \\
        -d "login=admin&password=admin&admin=1" \\
        -X POST \\
        http://shm.local/user/auth.cgi
    );

    my $json_ret = decode_json( $ret );
    is( $json_ret->{status}, 200, 'Check auth status');

    $session_id = $json_ret->{session_id};
};

subtest 'Check auth with cookies' => sub {
    my $ret = qx(
        curl -s \\
        -b "session_id=$session_id" \\
        -X GET \\
        http://shm.local/admin/user.cgi
    );

    my $json_ret = decode_json( $ret );
    is( scalar @{ $json_ret }, 4 );
};

subtest 'Check auth with incorrect cookies' => sub {
    my $ret = qx(
        curl -s \\
        -b "session_id=df2342fsdfs" \\
        -X GET \\
        http://shm.local/admin/user.cgi
    );

    my $json_ret = decode_json( $ret );
    is( $json_ret->{status}, 401 );
};

subtest 'Check access with incorrect cookies' => sub {
    my $ret = qx(
        curl -s \\
        -b "session_id=34fsdffs2" \\
        -X GET \\
        http://shm.local/admin/user.cgi
    );

    my $json_ret = decode_json( $ret );
    is( $json_ret->{status}, 401 );
};

subtest 'Check access without cookies' => sub {
    my $ret = qx(
        curl -s http://shm.local/admin/user.cgi
    );

    my $json_ret = decode_json( $ret );
    is( $json_ret->{status}, 401 );
};

done_testing();
