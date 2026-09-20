use v5.14;
use utf8;

use Test::More;
use Test::Deep;

use Core::Utils qw/
    decode_json
/;

sub api_get {
    my ( $url, %auth ) = @_;

    my $auth_opt = '';
    if ( $auth{login} ) {
        $auth_opt = qq{-H "login: $auth{login}" -H "password: $auth{password}"};
    }

    my $ret = qx(
        curl -s \\
        $auth_opt \\
        "http://api/shm/v1/$url"
    );

    return decode_json( $ret );
}

subtest '/system/locations - requires auth' => sub {
    my $json = api_get('system/locations');
    is( $json->{status}, 401, 'unauthenticated request is rejected' );
};

subtest '/system/locations - user-facing locations only' => sub {
    my $json = api_get( 'system/locations?limit=0', login => 'admin', password => 'admin' );

    ok( scalar @{ $json->{data} } > 0, 'some locations are returned' );

    my %by_location = map { $_->{location} => $_ } @{ $json->{data} };

    ok( !exists $by_location{'/admin/user'}, 'admin-only locations are excluded' );
    ok( exists $by_location{'/user'}, '/user is present' );

    for my $item ( @{ $json->{data} } ) {
        unlike( $item->{location}, qr{^/admin/}, 'no /admin/* location leaks into the user-facing list' );
        for my $m ( @{ $item->{methods} } ) {
            ok( $m->{method} =~ /^(GET|PUT|POST|DELETE)$/, 'method is one of the known HTTP verbs' );
        }
    }

    # /user/captcha and /system/auth are skip_check_auth-only endpoints and
    # must not be listed at all (no methods would remain for them).
    ok( !exists $by_location{'/user/captcha'}, 'skip_check_auth-only locations are fully excluded' );
};

subtest '/admin/system/locations - admin-only locations, requires admin' => sub {
    my $json = api_get( 'admin/system/locations?limit=0', login => 'admin', password => 'admin' );

    ok( scalar @{ $json->{data} } > 0, 'some admin locations are returned' );

    my %by_location = map { $_->{location} => $_ } @{ $json->{data} };
    ok( exists $by_location{'/admin/user'}, '/admin/user is present' );

    for my $item ( @{ $json->{data} } ) {
        like( $item->{location}, qr{^/admin/}, 'every location is under /admin/' );
    }
};

subtest '/admin/system/locations - forbidden for a non-admin (but valid) user' => sub {
    my $login = sprintf( 'locations_test_%d', time );
    my $password = 'testpass123';

    my $reg = decode_json( qx(
        curl -s \\
        -H "Content-Type: application/json" \\
        -X PUT \\
        -d '{"login":"$login","password":"$password"}' \\
        "http://api/shm/v1/user"
    ) );
    my $user_id = $reg->{data}->[0]->{user_id};
    ok( $user_id, 'test user registered' );

    my $json = api_get( 'admin/system/locations', login => $login, password => $password );
    is( $json->{status}, 403, 'non-admin user is forbidden (gid != 1)' );

    qx(
        curl -s \\
        -H "login: admin" -H "password: admin" \\
        -X DELETE \\
        "http://api/shm/v1/admin/user?user_id=$user_id&force=1"
    ) if $user_id;
};

done_testing();
