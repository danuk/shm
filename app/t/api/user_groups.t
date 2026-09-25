use v5.14;
use utf8;

use Test::More;
use Test::Deep;

use Core::Utils qw/
    decode_json
/;

# curl helper: JSON body + Basic-like login/password headers used across this
# codebase's API tests (see t/api/payment.t, t/api/auth.t).
sub api_call {
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

my $gid;

subtest 'PUT /v1/admin/user/group - create' => sub {
    my $json = api_call(
        method => 'PUT',
        url    => 'admin/user/group',
        data   => '{"name":"test-group","is_admin":0,"default_policy":"allow","rules":[{"action":"allow","uri":"*","methods":["GET"]}]}',
    );

    ok( $json->{data}->[0]->{gid}, 'new group has a gid' );
    is( $json->{data}->[0]->{name}, 'test-group', 'name is saved' );
    is( $json->{data}->[0]->{is_admin}, 0, 'is_admin is saved' );
    is( $json->{data}->[0]->{default_policy}, 'allow', 'default_policy is saved' );
    cmp_deeply( $json->{data}->[0]->{rules}, [ { action => 'allow', uri => '*', methods => ['GET'] } ], 'rules are saved as-is' );

    $gid = $json->{data}->[0]->{gid};
};

subtest 'GET /v1/admin/user/group - list/filter' => sub {
    my $json = api_call( method => 'GET', url => "admin/user/group?gid=$gid" );

    is( $json->{items}, 1, 'exactly one group found by gid' );
    is( $json->{data}->[0]->{gid}, $gid, 'correct group returned' );
};

subtest 'POST /v1/admin/user/group - update' => sub {
    my $json = api_call(
        method => 'POST',
        url    => 'admin/user/group',
        data   => qq({"gid":$gid,"name":"test-group-renamed","is_admin":1,"default_policy":"deny","rules":[{"action":"deny","uri":"/admin/*","methods":["*"]}]}),
    );

    is( $json->{data}->[0]->{name}, 'test-group-renamed', 'name is updated' );
    is( $json->{data}->[0]->{is_admin}, 1, 'is_admin is updated' );
    is( $json->{data}->[0]->{default_policy}, 'deny', 'default_policy is updated' );
    cmp_deeply( $json->{data}->[0]->{rules}, [ { action => 'deny', uri => '/admin/*', methods => ['*'] } ], 'rules are updated' );
};

subtest 'DELETE /v1/admin/user/group - delete' => sub {
    my $json = api_call( method => 'DELETE', url => "admin/user/group?gid=$gid" );
    ok( !$json->{error}, 'group is deleted without error' );

    $json = api_call( method => 'GET', url => "admin/user/group?gid=$gid" );
    is( $json->{items}, 0, 'group no longer exists' );
};

subtest 'System group (gid=1) is protected' => sub {
    my $json = api_call(
        method => 'POST',
        url    => 'admin/user/group',
        data   => '{"gid":1,"name":"hacked"}',
    );
    is( $json->{status}, 403, 'modifying gid=1 is forbidden' );

    $json = api_call( method => 'DELETE', url => 'admin/user/group?gid=1' );
    is( $json->{status}, 403, 'deleting gid=1 is forbidden' );

    $json = api_call( method => 'GET', url => 'admin/user/group?gid=1' );
    is( $json->{data}->[0]->{name}, 'admins', 'system group is unchanged' );
};

done_testing();
