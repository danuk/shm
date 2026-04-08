package Core::User::Captcha;

use v5.14;

use base qw(Exporter);

our @EXPORT_OK = qw(
    gen_captcha
    verify_captcha
);

use Core::Base qw(cfg);
use Core::Utils qw(
    encode_base64
    encode_base64url
    decode_base64url
);
use Digest::SHA qw(hmac_sha1 sha256_hex);
use Math::Random::Secure qw(rand);

sub gen_captcha {
    my $self = shift;

    my $a  = int( rand(9) ) + 1;
    my $b  = int( rand(9) ) + 1;
    my $op = int( rand(2) ) ? '+' : '-';
    ( $a, $b ) = ( $b, $a ) if $op eq '-' && $b > $a;

    my $answer    = $op eq '+' ? $a + $b : $a - $b;
    my $timestamp = time();
    my $secret    = cfg('billing')->{captcha_secret} // 'shm_captcha_default_key';

    my $answer_hash = sha256_hex( "$answer|$secret" );
    my $sig   = hmac_sha1( "$answer_hash|$timestamp", $secret );
    my $token = encode_base64url( "$answer_hash|$timestamp|$sig" );
    $token =~ s/=+$//;

    my $question = "$a $op $b = ?";
    my $image = gen_captcha_svg( $question );

    return {
        image => $image,
        token => $token,
    };
}

sub verify_captcha {
    my $self = shift;
    my %args = (
        token  => undef,
        answer => undef,
        @_,
    );

    return 0 unless defined $args{token} && defined $args{answer};

    my $raw = eval { decode_base64url( $args{token} ) };
    return 0 if $@ || !$raw;

    my ( $stored_answer_hash, $timestamp, $sig ) = split /\|/, $raw, 3;
    return 0 unless defined $stored_answer_hash && defined $timestamp && defined $sig;
    return 0 if time() - $timestamp > 300;  # 5 minute expiry

    my $secret   = cfg('billing')->{captcha_secret} // 'shm_captcha_default_key';
    my $expected = hmac_sha1( "$stored_answer_hash|$timestamp", $secret );

    # Constant-time comparison to prevent timing attacks
    return 0 unless length($sig) == length($expected);
    my $diff = 0;
    for my $i ( 0 .. length($sig) - 1 ) {
        $diff |= ord( substr($sig, $i, 1) ) ^ ord( substr($expected, $i, 1) );
    }
    return 0 if $diff;

    my $answer_hash = sha256_hex( "$args{answer}|$secret" );
    return $stored_answer_hash eq $answer_hash ? 1 : 0;
}

sub gen_captcha_svg {
    my $text = shift;

    my $width  = 200;
    my $height = 70;

    my @chars = split //, $text;
    my $chars_svg = '';
    my $x = 15;

    for my $ch ( @chars ) {
        my $y      = 35 + int( rand(20) ) - 10;
        my $rotate = int( rand(30) ) - 15;
        my $size   = 24 + int( rand(8) );
        my @fonts  = ('monospace', 'serif', 'sans-serif');
        my $font   = $fonts[ int( rand( scalar @fonts ) ) ];
        $chars_svg .= sprintf(
            '<text x="%d" y="%d" font-size="%d" font-family="%s" fill="#333" transform="rotate(%d %d %d)">%s</text>',
            $x, $y, $size, $font, $rotate, $x, $y, $ch eq '&' ? '&amp;' : $ch,
        );
        $x += $ch eq ' ' ? 10 : 18 + int( rand(5) );
    }

    my $lines_svg = '';
    for ( 1 .. 4 ) {
        my ($x1, $y1, $x2, $y2) = ( int(rand($width)), int(rand($height)), int(rand($width)), int(rand($height)) );
        my @colors = ('#999','#aaa','#bbb','#888');
        $lines_svg .= sprintf(
            '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>',
            $x1, $y1, $x2, $y2, $colors[ int(rand(scalar @colors)) ],
        );
    }

    my $dots_svg = '';
    for ( 1 .. 30 ) {
        my ($cx, $cy) = ( int(rand($width)), int(rand($height)) );
        $dots_svg .= sprintf( '<circle cx="%d" cy="%d" r="1" fill="#aaa"/>', $cx, $cy );
    }

    my $svg = sprintf(
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
        . '<rect width="100%%" height="100%%" fill="#f5f5f5"/>'
        . '%s%s%s'
        . '</svg>',
        $width, $height, $width, $height,
        $lines_svg, $dots_svg, $chars_svg,
    );

    return encode_base64( $svg, '' );
}

1;
