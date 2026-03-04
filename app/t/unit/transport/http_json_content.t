use v5.14;
use utf8;
use open ':std', ':encoding(UTF-8)';

use Test::More;
use Test::Deep;
use HTTP::Response;
use Core::Transport::Http; # monkey-patches HTTP::Response::json_content

sub make_response {
    my %args = (
        code         => 200,
        content_type => 'application/json; charset=utf-8',
        content      => '{}',
        @_,
    );

    my $response = HTTP::Response->new( $args{code} );
    $response->header( 'Content-Type' => $args{content_type} );
    $response->content( $args{content} );
    return $response;
}

subtest 'Successful JSON responses' => sub {
    my $r = make_response( content => '{"status":200,"data":[1,2,3]}' );
    cmp_deeply(
        $r->json_content,
        { status => 200, data => [1, 2, 3] },
        'valid JSON object decoded correctly',
    );

    my $arr = make_response( content => '[1,2,3]' );
    cmp_deeply( $arr->json_content, [1, 2, 3], 'JSON array decoded correctly' );

    my $empty = make_response( content => '{}' );
    cmp_deeply( $empty->json_content, {}, 'empty JSON object' );
};

subtest 'UTF-8 content' => sub {
    use Encode qw(encode_utf8);

    my $json_str = encode_utf8('{"error":"Вход с IP запрещён","status":403}');
    my $r = make_response( code => 403, content => $json_str );
    my $data = $r->json_content;
    ok( defined $data, 'json_content returns defined for UTF-8 error response' );
    is( $data->{status}, 403, 'status field parsed' );
    ok( length($data->{error}) > 0, 'error field is non-empty' );
};

subtest 'Non-JSON content types' => sub {
    my $html = make_response(
        content_type => 'text/html; charset=utf-8',
        content      => '<html>error</html>',
    );
    is( $html->json_content, undef, 'text/html returns undef' );

    my $plain = make_response(
        content_type => 'text/plain',
        content      => 'just text',
    );
    is( $plain->json_content, undef, 'text/plain returns undef' );

    my $no_ct = HTTP::Response->new(200);
    is( $no_ct->json_content, undef, 'missing Content-Type returns undef' );
};

subtest 'Error HTTP responses with JSON body' => sub {
    my $forbidden = make_response(
        code    => 403,
        content => '{"error":"Login from IP 172.18.0.1 is prohibited","status":403}',
    );
    my $data = $forbidden->json_content;
    ok( defined $data, '403 with JSON body returns defined' );
    is( $data->{error}, 'Login from IP 172.18.0.1 is prohibited', 'error message extracted' );
    is( $data->{status}, 403, 'status field extracted' );

    my $server_err = make_response(
        code    => 500,
        content => '{"error":"Internal error"}',
    );
    is( $server_err->json_content->{error}, 'Internal error', '500 JSON body parsed' );
};

subtest 'Invalid JSON' => sub {
    my $bad = make_response( content => 'not json at all' );
    my $result = eval { $bad->json_content };
    # should either return undef or die — either way should not silently return garbage
    if ($@) {
        pass('invalid JSON throws exception (caught by eval)');
    } else {
        is($result, undef, 'invalid JSON returns undef');
    }
};

done_testing();
