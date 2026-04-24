use v5.14;
use utf8;

use Test::More;
use Test::Deep;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

# Set request user context to admin so auto_fill user_id works in service layer.
my $admin = SHM->new( user_id => 1 );
ok( $admin && $admin->is_admin, 'admin context initialized' );

my $api_tokens = get_service('Api::Tokens');
ok( $api_tokens, 'Api::Tokens service loaded' );

my $created;

subtest 'create_token stores hashed token and auto-fills user_id' => sub {
    $created = $api_tokens->create_token(
        name   => 'test token',
        scopes => {
            'admin/user' => ['get', 'post'],
        },
    );

    ok( $created->{id}, 'token row id returned' );
    ok( $created->{token}, 'plaintext token returned' );
    is( length($created->{token}), 64, 'plaintext token has expected length' );

    my ($row) = $api_tokens->_list(
        fields => 'id,user_id,token,scopes',
        where  => { id => $created->{id} },
        limit  => 1,
    );

    ok( $row, 'token row found in DB' );
    is( $row->{user_id}, 1, 'user_id auto-filled from admin context' );
    isnt( $row->{token}, $created->{token}, 'stored token is hashed, not plaintext' );
    cmp_deeply( $row->{scopes}, { 'admin/user' => [ 'get', 'post' ] }, 'scopes saved как JSON' );
};

subtest 'validate returns token row with user_id for auth context' => sub {
    my $row = $api_tokens->validate( token => $created->{token} );

    ok( $row, 'validate succeeds for created token' );
    is( $row->{id}, $created->{id}, 'validate returns matching token id' );
    is( $row->{user_id}, 1, 'validate returns user_id required by SHM bearer auth' );
};

subtest 'validate fails for unknown token' => sub {
    my $row = $api_tokens->validate( token => 'unknown-token-value' );
    is( $row, undef, 'unknown token is rejected' );
};

subtest 'check_scope validates route + method mapping' => sub {
    my $row = $api_tokens->validate( token => $created->{token} );

    is( $api_tokens->check_scope( $row, '/admin/user', 'GET' ), 1, 'GET allowed by get scope' );
    is( $api_tokens->check_scope( $row, '/admin/user', 'POST' ), 1, 'POST allowed by post scope' );
    is( $api_tokens->check_scope( $row, '/admin/user', 'DELETE' ), 0, 'DELETE denied without delete scope' );
    is( $api_tokens->check_scope( $row, '/admin/service', 'GET' ), 0, 'unlisted route denied' );
};

# Cleanup created token.
if ( $created && $created->{id} ) {
    $api_tokens->_delete( where => { id => $created->{id} } );
}

$admin->commit;

done_testing();
