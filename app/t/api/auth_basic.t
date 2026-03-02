use v5.14;
use utf8;

use Test::More;
use Core::Utils qw/decode_json/;

subtest 'Check Basic auth for Admin' => sub {
    my $ret = qx(
        curl -s \\
        -u admin:admin \\
        http://api/shm/v1/user
    );

    my $json_ret = decode_json( $ret );

    is( exists $json_ret->{data}, 1);
};

subtest 'Check Basic auth for User' => sub {
    my $ret = qx(
        curl -s \\
        -u danuk:danuk \\
        http://api/shm/v1/user
    );

    my $json_ret = decode_json( $ret );
    is( exists $json_ret->{data} , 1);
    is( $json_ret->{data}->[0]->{user_id}, 40092);
};

done_testing();
