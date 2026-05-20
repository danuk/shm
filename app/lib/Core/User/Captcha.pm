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
    my $pixel_size = 3;

    my %font_pixels = (
        '0' => [
            '00111',
            '11001',
            '10101',
            '10101',
            '10101',
            '11001',
            '00111',
        ],
        '1' => [
            '00010',
            '00110',
            '00010',
            '00010',
            '00010',
            '00010',
            '00111',
        ],
        '2' => [
            '01110',
            '10001',
            '00001',
            '00100',
            '01000',
            '10000',
            '11111',
        ],
        '3' => [
            '11110',
            '00001',
            '00001',
            '01110',
            '00001',
            '00001',
            '11110',
        ],
        '4' => [
            '00100',
            '01100',
            '10100',
            '10001',
            '11111',
            '00001',
            '00001',
        ],
        '5' => [
            '11111',
            '10000',
            '10000',
            '11110',
            '00001',
            '00001',
            '11110',
        ],
        '6' => [
            '01110',
            '10000',
            '10000',
            '11110',
            '10001',
            '10001',
            '01110',
        ],
        '7' => [
            '11111',
            '00001',
            '00001',
            '00010',
            '00100',
            '01000',
            '10000',
        ],
        '8' => [
            '01110',
            '10001',
            '10001',
            '01110',
            '10001',
            '10001',
            '01110',
        ],
        '9' => [
            '01110',
            '10001',
            '10001',
            '01111',
            '00001',
            '00001',
            '01110',
        ],
        '+' => [
            '00000',
            '00100',
            '00100',
            '11111',
            '00100',
            '00100',
            '00000',
        ],
        '-' => [
            '00000',
            '00000',
            '00000',
            '11111',
            '00000',
            '00000',
            '00000',
        ],
        ' ' => [
            '00000',
            '00000',
            '00000',
            '00000',
            '00000',
            '00000',
            '00000',
        ],
        '=' => [
            '00000',
            '11111',
            '00000',
            '11111',
            '00000',
            '00000',
            '00000',
        ],
        '?' => [
            '01110',
            '10001',
            '00001',
            '00110',
            '00100',
            '00000',
            '00100',
        ],
    );

    my $chars_svg = '';

    # Предварительный расчет ширины для центрирования
    my @all_chars = split //, $text;
    my $char_count = 0;
    for my $ch (@all_chars) {
        $char_count++ if exists $font_pixels{$ch};
    }
    my $total_width = $char_count * 15 + ($char_count - 1) * 8;
    my $x_offset = ($width - $total_width) / 2;
    if ($x_offset < 5) { $x_offset = 5; }

    for my $ch ( split //, $text ) {
        next unless exists $font_pixels{$ch};

        my @rows = @{ $font_pixels{$ch} };
        my $y_offset = 20 + int( rand(10) );
        my $rotate_angle = int( rand(40) ) - 20;

        my $noise_x = int( rand(4) ) - 2;
        my $noise_y = int( rand(4) ) - 2;

        for my $row_idx ( 0 .. @rows - 1 ) {
            my $row = $rows[$row_idx];
            for my $col_idx ( 0 .. length($row) - 1 ) {
                if ( substr($row, $col_idx, 1) eq '1' ) {
                    my $px = $x_offset + $col_idx * $pixel_size + $noise_x;
                    my $py = $y_offset + $row_idx * $pixel_size + $noise_y;

                    my @colors = ('#222', '#333', '#444', '#555');
                    my $color = $colors[ int( rand( scalar @colors ) ) ];
                    my $opacity = 0.6 + rand(0.4);

                    $chars_svg .= sprintf(
                        '<rect x="%d" y="%d" width="%d" height="%d" fill="%s" opacity="%.2f" '
                        . 'transform="rotate(%d %d %d)"/>',
                        $px, $py, $pixel_size - 1, $pixel_size - 1, $color, $opacity,
                        $rotate_angle, $x_offset + $col_idx * $pixel_size / 2, $y_offset + $row_idx * $pixel_size / 2,
                    );
                }
            }
        }

        $x_offset += 15 + int( rand(3) );
    }

    my $noise_svg = '';
    for ( 1 .. 20 ) {
        my $nx = int( rand($width) );
        my $ny = int( rand($height) );
        my $nr = 1 + int( rand(3) );
        my @noise_colors = ('#e5e5e5', '#efefef', '#e0e0e0', '#ddd');
        $noise_svg .= sprintf(
            '<circle cx="%d" cy="%d" r="%d" fill="%s" opacity="0.4"/>',
            $nx, $ny, $nr, $noise_colors[ int( rand( scalar @noise_colors ) ) ],
        );
    }

    my $lines_svg = '';
    for ( 1 .. 8 ) {
        my $x1 = int( rand($width) );
        my $y1 = int( rand($height) );
        my $x2 = int( rand($width) );
        my $y2 = int( rand($height) );
        $lines_svg .= sprintf(
            '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#ddd" stroke-width="1" opacity="0.3"/>',
            $x1, $y1, $x2, $y2,
        );
    }

    my $svg = sprintf(
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
        . '<rect width="100%%" height="100%%" fill="#f5f5f5"/>'
        . '%s%s%s'
        . '</svg>',
        $width, $height, $width, $height,
        $noise_svg, $lines_svg, $chars_svg,
    );

    return encode_base64( $svg, '' );
}

1;
