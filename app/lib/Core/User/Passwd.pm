package Core::User::Passwd;

use v5.14;

use Digest::SHA qw(sha1_hex sha256_hex hmac_sha512);
use Math::Random::Secure qw(rand);

# PBKDF2-HMAC-SHA512 (RFC 2898).
# Args: ($password, $salt_bytes, $iterations, $dklen)
# Returns: $dklen raw bytes of derived key.
sub _pbkdf2 {
    my ( $password, $salt, $iterations, $dklen ) = @_;
    $dklen //= 32;

    my $hlen        = 64;    # SHA-512 output is 64 bytes
    my $block_count = int( ( $dklen + $hlen - 1 ) / $hlen );
    my $dk          = '';

    for my $i ( 1 .. $block_count ) {
        my $u = hmac_sha512( $salt . pack( 'N', $i ), $password );
        my $t = $u;
        for ( 2 .. $iterations ) {
            $u  = hmac_sha512( $u, $password );
            $t ^= $u;
        }
        $dk .= $t;
    }

    return substr( $dk, 0, $dklen );
}

# Create a new password hash using scheme $7$ (PBKDF2-HMAC-SHA512, 100_000 iterations).
# Format: $7$<iterations>$<salt_hex>$<dk_hex>
sub make_password {
    my $self  = shift;
    my $plain = shift;

    my $iterations = 100_000;
    my $salt       = pack( 'C*', map { int( rand(256) ) } 1..16 );
    my $dk         = _pbkdf2( $plain, $salt, $iterations, 32 );

    return sprintf( '$7$%d$%s$%s',
        $iterations, unpack( 'H*', $salt ), unpack( 'H*', $dk ) );
}

# Verify a password against a stored hash.
# Auto-detects scheme by prefix; legacy hashes used the login as salt.
sub verify_password {
    my $self   = shift;
    my $plain  = shift;
    my $stored = shift;
    my $login  = shift;    # needed only for legacy (no-prefix) hashes

    if ( $stored =~ /^\$7\$(\d+)\$([0-9a-f]+)\$([0-9a-f]+)$/ ) {
        # Scheme $7$: PBKDF2-HMAC-SHA512
        my ( $iter, $salt_hex, $expected ) = ( $1 + 0, $2, $3 );
        my $dk = _pbkdf2( $plain, pack( 'H*', $salt_hex ), $iter, 32 );
        return unpack( 'H*', $dk ) eq $expected ? 1 : 0;
    } else {
        # Legacy: sha1(login--password)
        return sha1_hex( join '--', $login, $plain ) eq $stored ? 1 : 0;
    }
}

1;
