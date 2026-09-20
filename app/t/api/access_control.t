use v5.14;
use utf8;

use Test::More;
use Test::Deep;

use Core::Utils qw/
    decode_json
/;

sub admin_call {
    my %args = (
        method => 'GET',
        url    => undef,
        data   => undef,
        @_,
    );

    my $data_opt = defined $args{data} ? sprintf( q{-d '%s'}, $args{data} ) : '';

    my $ret = qx(
        curl -s \\
        -H "Content-Type: application/json" \\
        -H "login: admin" \\
        -H "password: admin" \\
        -X $args{method} \\
        $data_opt \\
        "http://api/shm/v1/$args{url}"
    );

    return decode_json( $ret );
}

sub call_as {
    my %args = (
        method => 'GET',
        url    => undef,
        login  => undef,
        password => undef,
        session_id => undef,
        @_,
    );

    my $auth_opt = $args{session_id}
        ? sprintf( q{-b "session_id=%s"}, $args{session_id} )
        : sprintf( q{-H "login: %s" -H "password: %s"}, $args{login}, $args{password} );

    my $ret = qx(
        curl -s \\
        -X $args{method} \\
        $auth_opt \\
        "http://api/shm/v1/$args{url}"
    );

    return decode_json( $ret );
}

# --- Setup: dedicated test user (not used by any other test) ---

my $login = sprintf( 'access_ctrl_%d', time );
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

my $gid_restricted;
my $gid_account;
my $gid_custom_admin;

END {
    # best-effort cleanup, regardless of test outcome
    admin_call( method => 'DELETE', url => "admin/user?user_id=$user_id&force=1" ) if $user_id;
    admin_call( method => 'DELETE', url => "admin/user/group?gid=$gid_restricted" ) if $gid_restricted;
    admin_call( method => 'DELETE', url => "admin/user/group?gid=$gid_account" ) if $gid_account;
    admin_call( method => 'DELETE', url => "admin/user/group?gid=$gid_custom_admin" ) if $gid_custom_admin;
}

subtest 'Without gid, behaviour is unchanged (legacy)' => sub {
    my $json = call_as( url => 'user', login => $login, password => $password );
    is( $json->{status}, 200, 'GET /user works without a group' );

    $json = call_as( url => 'user/accounts', login => $login, password => $password );
    is( $json->{status}, 200, 'GET /user/accounts works without a group' );

    $json = call_as( url => 'admin/user', login => $login, password => $password );
    is( $json->{status}, 403, '/admin/* is still forbidden without gid=1' );
};

subtest 'User-group deny restricts access (Basic-like auth)' => sub {
    my $created = admin_call(
        method => 'PUT',
        url    => 'admin/user/group',
        data   => '{"name":"access-ctrl-test","is_admin":0,"default_policy":"allow","rules":[{"action":"deny","uri":"/user/accounts","methods":["*"]}]}',
    );
    $gid_restricted = $created->{data}->[0]->{gid};
    ok( $gid_restricted, 'restricted group created' );

    admin_call( method => 'POST', url => 'admin/user', data => qq({"user_id":$user_id,"gid":$gid_restricted}) );

    my $json = call_as( url => 'user', login => $login, password => $password );
    is( $json->{status}, 200, 'allowed location still works' );

    $json = call_as( url => 'user/accounts', login => $login, password => $password );
    is( $json->{status}, 403, 'denied location is forbidden' );
};

subtest 'User-group deny restricts access (session/cookie auth)' => sub {
    my $auth = decode_json( qx(
        curl -s \\
        -H "Content-Type: application/json" \\
        -X POST \\
        -d '{"login":"$login","password":"$password"}' \\
        "http://api/shm/v1/user/auth"
    ) );
    my $session_id = $auth->{id};
    ok( $session_id, 'session created' );

    my $json = call_as( url => 'user', session_id => $session_id );
    is( $json->{status}, 200, 'allowed location works via session' );

    $json = call_as( url => 'user/accounts', session_id => $session_id );
    is( $json->{status}, 403, 'denied location is forbidden via session (same restriction as Basic auth)' );
};

subtest 'Account group can only narrow, never widen, access' => sub {
    # Reset user's own group to unrestricted, so only the account-level
    # group is responsible for narrowing access below.
    admin_call( method => 'POST', url => 'admin/user', data => qq({"user_id":$user_id,"gid":0}) );

    my $json = call_as( url => 'user/accounts', login => $login, password => $password );
    is( $json->{status}, 200, 'accounts is reachable again once user gid is cleared' );

    my $created = admin_call(
        method => 'PUT',
        url    => 'admin/user/group',
        data   => '{"name":"access-ctrl-account","is_admin":0,"default_policy":"allow","rules":[{"action":"deny","uri":"/user/accounts","methods":["*"]}]}',
    );
    $gid_account = $created->{data}->[0]->{gid};
    ok( $gid_account, 'account-level group created' );

    admin_call(
        method => 'POST',
        url    => 'admin/user/accounts',
        data   => qq({"user_id":$user_id,"login":"$login","type":"login","settings":{"gid":$gid_account}}),
    );

    $json = call_as( url => 'user', login => $login, password => $password );
    is( $json->{status}, 200, 'unrelated location is still reachable' );

    $json = call_as( url => 'user/accounts', login => $login, password => $password );
    is( $json->{status}, 403, 'account-level group narrows access even though user gid is unrestricted' );

    # Clear the account-level restriction
    admin_call(
        method => 'POST',
        url    => 'admin/user/accounts',
        data   => qq({"user_id":$user_id,"login":"$login","type":"login","settings":{}}),
    );

    $json = call_as( url => 'user/accounts', login => $login, password => $password );
    is( $json->{status}, 200, 'access is restored once the account-level gid is cleared' );
};

subtest 'is_admin is a group flag, not tied to a specific gid' => sub {
    # Custom (non-system, non-gid=1) group with is_admin=1 must unlock
    # /admin/* just like the built-in admins group does.
    my $created = admin_call(
        method => 'PUT',
        url    => 'admin/user/group',
        data   => '{"name":"access-ctrl-custom-admin","is_admin":1,"default_policy":"allow","rules":[]}',
    );
    $gid_custom_admin = $created->{data}->[0]->{gid};
    ok( $gid_custom_admin, 'custom admin-flagged group created' );

    admin_call( method => 'POST', url => 'admin/user', data => qq({"user_id":$user_id,"gid":$gid_custom_admin}) );

    my $json = call_as( url => 'admin/user', login => $login, password => $password );
    is( $json->{status}, 200, 'a custom group with is_admin=1 unlocks /admin/*, even though gid != 1' );

    # Flip is_admin off again on the same group - /admin/* must be blocked,
    # even though nothing else about the group (its rules) changed.
    admin_call(
        method => 'POST',
        url    => 'admin/user/group',
        data   => qq({"gid":$gid_custom_admin,"is_admin":0}),
    );

    $json = call_as( url => 'admin/user', login => $login, password => $password );
    is( $json->{status}, 403, 'the same group with is_admin=0 blocks /admin/* again' );

    # Reset the test user's own gid to avoid leaking state into cleanup order
    admin_call( method => 'POST', url => 'admin/user', data => qq({"user_id":$user_id,"gid":0}) );
};

done_testing();
