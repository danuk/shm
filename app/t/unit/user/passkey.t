use v5.14;
use utf8;

use Test::More;
binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw( output failure_output todo_output );
use Core::User::Passkey;
use Digest::SHA qw( sha256 );
use MIME::Base64 qw( decode_base64url encode_base64url );

# Без базы и Redis, подменяем cfg() и кэш
my %cfg = ( rp_id => 'example.com' );

{
    package FakeRedis;
    sub new { bless { store => $_[1] }, $_[0] }
    # как в Redis, возвращает число удаленных ключей
    sub del { my ( $self, $key ) = @_; return 0 unless exists $self->{store}{$key}; delete $self->{store}{$key}; 1 }

    package FakeCache;
    sub new { my $store = {}; bless { store => $store, redis => FakeRedis->new($store) }, shift }
    sub set { my ( $self, $key, $value ) = @_; $self->{store}{$key} = $value; 1 }
    sub get { my ( $self, $key ) = @_; $self->{store}{$key} }
    sub delete { my ( $self, $key ) = @_; my $v = $self->get($key); $self->redis->del($key) if $v; $v }
    sub redis { $_[0]{redis} }
}
my $cache = FakeCache->new;

no warnings 'redefine';
local *Core::User::Passkey::cfg = sub { $_[0] eq 'passkey' ? {%cfg} : {} };
local *Core::User::Passkey::get_service = sub { $cache };
use warnings 'redefine';

my $pk = bless {}, 'Core::User::Passkey';

subtest 'generate_challenge' => sub {
    my $public = $pk->generate_challenge();
    is( length( decode_base64url($public) ), 32, '32 байта' );
    is( $cache->get("passkey_challenge:$public"), 0, 'публичный challenge хранит 0' );

    my $reg = $pk->generate_challenge(42);
    is( $cache->get("passkey_challenge:$reg"), 42, 'challenge регистрации хранит user_id' );

    my %seen = map { $pk->generate_challenge() => 1 } 1 .. 200;
    is( scalar keys %seen, 200, 'без повторов' );
};

subtest 'verify_challenge' => sub {
    my $login = $pk->generate_challenge();
    ok( !$pk->verify_challenge( $login, 42 ), 'challenge входа не годится для регистрации' );
    ok( $pk->verify_challenge($login), 'challenge входа принят' );
    ok( !$pk->verify_challenge($login), 'второй раз нельзя' );

    my $reg = $pk->generate_challenge(42);
    ok( !$pk->verify_challenge($reg), 'challenge регистрации не годится для входа' );
    ok( !$pk->verify_challenge( $reg, 43 ), 'чужой user_id' );
    ok( $pk->verify_challenge( $reg, 42 ), 'свой user_id' );
    ok( !$pk->verify_challenge( $reg, 42 ), 'второй раз нельзя' );

    ok( !$pk->verify_challenge('unknown'), 'неизвестный challenge' );
};

# authData для регистрации
sub auth_data {
    my %a = ( rp => 'example.com', flags => 0x45, cred_id => 'cred-id-bytes', @_ );
    return sha256( $a{rp} ) . chr( $a{flags} ) . "\0" x 4 . "\0" x 16
        . pack( 'n', length $a{cred_id} ) . $a{cred_id} . "\xa0";
}
my $cred = encode_base64url( 'cred-id-bytes', '' );

subtest '_check_registration_auth_data' => sub {
    is( $pk->_check_registration_auth_data( auth_data(), $cred ), undef, 'корректные данные' );
    is( $pk->_check_registration_auth_data( auth_data( rp => 'evil.com' ), $cred ), 'INVALID_RP_ID', 'чужой rpIdHash' );
    is( $pk->_check_registration_auth_data( auth_data( flags => 0x40 ), $cred ), 'USER_NOT_PRESENT', 'нет UP' );
    is( $pk->_check_registration_auth_data( auth_data( flags => 0x05 ), $cred ), 'INVALID_ATTESTATION_OBJECT', 'нет AT' );
    is( $pk->_check_registration_auth_data( auth_data(), encode_base64url( 'other', '' ) ), 'CREDENTIAL_ID_MISMATCH', 'credential_id не из authData' );
    is( $pk->_check_registration_auth_data( 'short', $cred ), 'INVALID_ATTESTATION_OBJECT', 'обрезанные данные' );

    local $cfg{user_verification} = 'required';
    is( $pk->_check_registration_auth_data( auth_data( flags => 0x41 ), $cred ), 'USER_NOT_VERIFIED', 'UV обязателен' );
    is( $pk->_check_registration_auth_data( auth_data( flags => 0x45 ), $cred ), undef, 'UV есть' );
};

subtest 'origins и user_verification' => sub {
    ok( $pk->check_origin( { origin => 'https://evil.example.com' } ), 'без origins не проверяем' );
    is( $pk->user_verification, 'preferred', 'по умолчанию preferred' );

    local $cfg{origins} = [ 'https://app.example.com' ];
    ok( $pk->check_origin( { origin => 'https://app.example.com' } ), 'разрешённый origin' );
    ok( !$pk->check_origin( { origin => 'https://evil.example.com' } ), 'поддомен rp_id вне списка' );
    ok( !$pk->check_origin( {} ), 'origin отсутствует' );

    local $cfg{user_verification} = 'required';
    is( $pk->user_verification, 'required', 'required из конфига' );
};

done_testing();
