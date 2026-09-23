use v5.14;
use utf8;

use Test::More;
use Core::User::Logins;
use Core::Utils qw( now add_period utime_to_string );
use Digest::SHA qw( sha256_hex );

# Перехватываем SUPER::add и смотрим, с какими аргументами логин уходит в базу
sub captured_add {
    my %args = @_;

    my %seen;
    no warnings 'redefine';
    local *Core::Base::add = sub {
        my ( $self, %a ) = @_;
        %seen = %a;
        return 1;
    };

    my $logins = bless {}, 'Core::User::Logins';
    my $ret = $logins->add( %args );

    return ( $ret, \%seen );
}

subtest 'add - keeps external provider type for email-like login' => sub {
    my ( $ret, $seen ) = captured_add( login => 'User@Example.com', type => 'google_oauth2' );

    ok( $ret, 'account is created' );
    is( $seen->{type}, 'google_oauth2', 'provider type is not replaced with email' );
    is( $seen->{login}, 'user@example.com', 'login is lowercased' );
};

subtest 'add - default type is still guessed by login format' => sub {
    my ( $ret, $seen ) = captured_add( login => 'user@example.com' );

    ok( $ret, 'account is created' );
    is( $seen->{type}, 'email', 'email login gets email type' );
};

subtest 'add - phone login keeps digits only' => sub {
    my ( $ret, $seen ) = captured_add( login => '+7 (900) 123-45-67', type => 'phone' );

    ok( $ret, 'account is created' );
    is( $seen->{type}, 'phone', 'phone type is kept' );
    is( $seen->{login}, '79001234567', 'phone login keeps digits only' );
};

subtest 'add - token type generates a random token and stores its sha256 hash' => sub {
    my ( $ret, $seen ) = captured_add( login => 'ignored-by-client', type => 'token', user_id => 42, primary => 1 );

    ok( ref $ret eq 'HASH', 'add returns a hash with the plain token' );
    is( $seen->{type}, 'token', 'token type is kept' );
    isnt( $seen->{login}, 'ignored-by-client', 'client supplied login is ignored' );
    is( length( $seen->{login} ), 64, 'stored login is a sha256 hex digest' );
    like( $seen->{login}, qr/^[0-9a-f]{64}$/, 'stored login looks like a sha256 hex digest' );
    is( sha256_hex( $ret->{login} ), $seen->{login}, 'returned plain token hashes to the stored login' );
    isnt( $ret->{login}, $seen->{login}, 'plain token differs from the stored hash' );
    ok( !exists $seen->{primary}, 'primary flag is stripped for token type' );
};

subtest 'add - token with ttl stores computed expire_at' => sub {
    my ( $ret, $seen ) = captured_add( type => 'token', user_id => 42, settings => { ttl => '30d' } );

    my $expected = add_period( now(), '30d' );

    is( $seen->{settings}->{expire_at}, $expected, 'expire_at is computed from ttl' );
    is( $ret->{settings}->{expire_at}, $expected, 'expire_at is returned to the client too' );
};

subtest 'add - token without ttl has no expire_at' => sub {
    my ( $ret, $seen ) = captured_add( type => 'token', user_id => 42 );

    ok( !exists $seen->{settings}->{expire_at}, 'expire_at is not set when ttl is not given' );
};

subtest 'add - token with invalid ttl format is rejected' => sub {
    my ( $ret, $seen ) = captured_add( type => 'token', user_id => 42, settings => { ttl => 'invalid' } );

    ok( !defined $ret, 'add returns undef for an invalid ttl' );
};

subtest 'is_expired - checks settings.expire_at against current time' => sub {
    my $logins = bless {}, 'Core::User::Logins';

    ok( !$logins->is_expired( { settings => {} } ), 'no expire_at means not expired' );
    ok( $logins->is_expired( { settings => { expire_at => utime_to_string( time - 86400 ) } } ), 'past expire_at is expired' );
    ok( !$logins->is_expired( { settings => { expire_at => utime_to_string( time + 86400 ) } } ), 'future expire_at is not expired' );
};

done_testing();
