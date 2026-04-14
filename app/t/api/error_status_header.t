use v5.14;
use utf8;

use Test::More;
use Core::Utils qw/decode_json/;

subtest 'Unauthorized request returns HTTP 401 and JSON status 401' => sub {
    my $raw = qx(curl -s -i http://api/shm/v1/user);

    my ($head, $body) = split(/\r?\n\r?\n/, $raw, 2);

    like(
        $head,
        qr/^HTTP\/\S+\s+401\b/m,
        'HTTP status line is 401',
    );

    my $json_ret = decode_json($body);
    is(
        $json_ret->{status},
        401,
        'JSON body status is 401',
    );
};

done_testing();
