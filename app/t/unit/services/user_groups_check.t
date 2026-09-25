use v5.14;
use utf8;

use Test::More;
use Core::User::Groups;

sub make_group {
    my %args = (
        default_policy => 'allow',
        rules => undef,
        @_,
    );

    return bless {
        res => {
            default_policy => $args{default_policy},
            rules          => $args{rules},
        },
    }, 'Core::User::Groups';
}

subtest 'default_policy=allow, no rules - allow everything' => sub {
    my $group = make_group( default_policy => 'allow' );

    ok( $group->check( uri => '/user', method => 'GET' ), 'GET /user is allowed' );
    ok( $group->check( uri => '/anything', method => 'DELETE' ), 'any location/method is allowed by default policy' );
};

subtest 'default_policy=deny, no rules - deny everything' => sub {
    my $group = make_group( default_policy => 'deny' );

    ok( !$group->check( uri => '/user', method => 'GET' ), 'nothing is allowed with a deny default policy and no rules' );
};

subtest 'a deny rule overrides an allow default policy at a specific point in the chain' => sub {
    my $group = make_group(
        default_policy => 'allow',
        rules => [
            { action => 'deny', uri => '/admin/*', methods => ['*'] },
        ],
    );

    ok( $group->check( uri => '/user', method => 'GET' ), 'non-admin location falls through to the allow default policy' );
    ok( !$group->check( uri => '/admin/user', method => 'GET' ), '/admin/* is denied by the explicit rule' );
};

subtest 'an allow rule overrides a deny default policy at a specific point in the chain' => sub {
    my $group = make_group(
        default_policy => 'deny',
        rules => [
            { action => 'allow', uri => '/user', methods => ['GET'] },
        ],
    );

    ok( $group->check( uri => '/user', method => 'GET' ), 'explicitly allowed location/method passes' );
    ok( !$group->check( uri => '/user', method => 'POST' ), 'same location but different method falls through to deny default policy' );
    ok( !$group->check( uri => '/other', method => 'GET' ), 'unrelated location falls through to deny default policy' );
};

subtest 'deny always wins over allow, regardless of list order' => sub {
    my $group = make_group(
        default_policy => 'deny',
        rules => [
            { action => 'allow', uri => '*',                methods => ['GET'] },
            { action => 'deny',  uri => '/admin/logs/api',   methods => ['GET'] },
        ],
    );

    ok( $group->check( uri => '/user', method => 'GET' ), 'unrelated location still matches the general allow rule' );
    ok( !$group->check( uri => '/admin/logs/api', method => 'GET' ),
        'a specific deny rule wins even though a broader allow rule is listed before it (regression: previously the first-listed allow rule shadowed the later deny rule)' );
};

subtest 'deny wins over allow even when deny is listed first' => sub {
    my $group = make_group(
        default_policy => 'deny',
        rules => [
            { action => 'deny',  uri => '/user/secret', methods => ['*'] },
            { action => 'allow', uri => '/user/*',       methods => ['GET'] },
        ],
    );

    ok( !$group->check( uri => '/user/secret', method => 'GET' ), 'deny /user/secret wins' );
    ok( $group->check( uri => '/user/other', method => 'GET' ), 'allow rule still applies to other locations' );
    ok( !$group->check( uri => '/user/other', method => 'DELETE' ), 'allow rule only covers GET, falls through to deny default policy' );
};

subtest 'method-specific rules' => sub {
    my $group = make_group(
        default_policy => 'deny',
        rules => [ { action => 'allow', uri => '*', methods => ['GET'] } ],
    );

    ok( $group->check( uri => '/user', method => 'GET' ), 'GET is allowed' );
    ok( !$group->check( uri => '/user', method => 'PUT' ), 'PUT is not allowed' );
};

subtest 'exact location match does not match sub-locations' => sub {
    my $group = make_group(
        default_policy => 'deny',
        rules => [ { action => 'allow', uri => '/user', methods => ['*'] } ],
    );

    ok( $group->check( uri => '/user', method => 'GET' ), 'exact match is allowed' );
    ok( !$group->check( uri => '/user/accounts', method => 'GET' ), 'sub-location is not allowed (no wildcard)' );
};

subtest 'prefix wildcard matches sub-locations only through the prefix' => sub {
    my $group = make_group(
        default_policy => 'deny',
        rules => [ { action => 'allow', uri => '/user/*', methods => ['*'] } ],
    );

    ok( $group->check( uri => '/user/accounts', method => 'GET' ), 'sub-location is allowed' );
    ok( !$group->check( uri => '/user', method => 'GET' ), 'the prefix itself (without trailing part) is not allowed' );
    ok( !$group->check( uri => '/userservice', method => 'GET' ), 'lookalike location without separator is not allowed' );
};

subtest 'is_system protects gid=1' => sub {
    my $admins = bless { res => { gid => 1 } }, 'Core::User::Groups';
    my $users  = bless { res => { gid => 2 } }, 'Core::User::Groups';

    ok( $admins->is_system, 'gid=1 is a system group' );
    ok( !$users->is_system, 'gid=2 is not a system group' );
};

done_testing();
