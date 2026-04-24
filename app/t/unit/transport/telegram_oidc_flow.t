use v5.14;
use warnings;
use utf8;
use Test::More;
use SHM;

$ENV{SHM_TEST} = 1;

{
    package Local::TestCache;

    sub new {
        my $class = shift;
        return bless { data => {} }, $class;
    }

    sub set_json {
        my ( $self, $key, $value, $ttl ) = @_;
        $self->{data}{$key} = $value;
        return 1;
    }

    sub get_json {
        my ( $self, $key ) = @_;
        return $self->{data}{$key};
    }

    sub delete {
        my ( $self, $key ) = @_;
        delete $self->{data}{$key};
        return 1;
    }
}

my $user = SHM->new( user_id => 40092 );
my $tg = $user->srv('Transport::Telegram');

my $fake_cache = Local::TestCache->new;

no warnings 'redefine';
no warnings 'once';
*Core::Transport::Telegram::cache = sub { return $fake_cache; };
*Core::Transport::Telegram::telegram_oidc_client_id = sub { return '6574873343'; };

subtest 'OIDC init generates URL and stores state context' => sub {
    my $ret = $tg->telegram_oidc_init(
        profile => 'telegram_bot',
        redirect_uri => 'https://example.com/shm/v1/telegram/web/callback',
        register_if_not_exists => 1,
        ttl => 600,
    );

    ok( ref $ret eq 'HASH', 'returns hash' );
    ok( $ret->{auth_url} =~ m{^https://oauth\.telegram\.org/auth\?}, 'auth_url generated' );
    like( $ret->{auth_url}, qr/client_id=6574873343/, 'auth_url contains client_id' );
    like( $ret->{auth_url}, qr/code_challenge_method=S256/, 'auth_url contains PKCE method' );

    ok( $ret->{state}, 'state generated' );
    ok( $ret->{nonce}, 'nonce generated' );
    ok( $ret->{code_challenge}, 'code_challenge generated' );
    is( $ret->{expires_in}, 600, 'ttl is returned' );

    my $cache_key = $tg->telegram_oidc_state_cache_key( $ret->{state} );
    my $ctx = $fake_cache->get_json( $cache_key );
    ok( ref $ctx eq 'HASH', 'state context saved in cache' );
    is( $ctx->{profile}, 'telegram_bot', 'profile saved in state context' );
    is( $ctx->{register_if_not_exists}, 1, 'register_if_not_exists saved in context' );
};

subtest 'Callback restores context by state and consumes it' => sub {
    my $init = $tg->telegram_oidc_init(
        profile => 'telegram_bot',
        redirect_uri => 'https://example.com/shm/v1/telegram/web/callback',
        register_if_not_exists => 1,
    );

    my $captured;
    local *Core::Transport::Telegram::web_auth = sub {
        my $self = shift;
        my %args = @_;
        $captured = \%args;
        return { session_id => 'test-session' };
    };

    my $ret = $tg->web_auth_callback(
        state => $init->{state},
        code => 'auth_code_123',
    );

    is( $ret->{session_id}, 'test-session', 'returns web_auth result' );
    is( $captured->{expected_state}, $init->{state}, 'expected_state restored from cache' );
    ok( $captured->{code_verifier}, 'code_verifier restored from cache' );
    is( $captured->{nonce}, $init->{nonce}, 'nonce restored from cache' );
    is( $captured->{register_if_not_exists}, 1, 'register_if_not_exists restored from cache' );

    my $cache_key = $tg->telegram_oidc_state_cache_key( $init->{state} );
    ok( !defined $fake_cache->get_json( $cache_key ), 'state context deleted after callback' );

    my $captured_second;
    local *Core::Transport::Telegram::web_auth = sub {
        my $self = shift;
        my %args = @_;
        $captured_second = \%args;
        return { session_id => 'test-session-2' };
    };

    $tg->web_auth_callback(
        state => $init->{state},
        code => 'auth_code_456',
    );

    ok( !defined $captured_second->{code_verifier}, 'consumed state does not restore code_verifier second time' );
};

subtest 'Callback redirects to return_url on success' => sub {
    my $init = $tg->telegram_oidc_init(
        profile => 'telegram_bot',
        redirect_uri => 'https://example.com/shm/v1/telegram/web/callback',
        return_url => 'https://example.com/lk/profile',
        register_if_not_exists => 1,
    );

    local *Core::Transport::Telegram::web_auth = sub {
        return { session_id => 'redirect-session' };
    };

    my $ret = $tg->web_auth_callback(
        state => $init->{state},
        code => 'auth_code_redirect',
    );

    is( $ret->{status}, 302, 'redirect status is 302' );
    like( $ret->{redirect}, qr/^https:\/\/example\.com\/lk\/profile\?/, 'redirect points to return_url' );
    like( $ret->{redirect}, qr/tg_status=success/, 'redirect contains tg_status=success' );
    like( $ret->{redirect}, qr/session_id=redirect-session/, 'redirect contains session_id' );
    is( $ret->{tg_status}, 'success', 'payload tg_status is success' );
    is( $ret->{session_id}, 'redirect-session', 'payload includes session_id' );
};

done_testing();
