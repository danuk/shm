use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use SHM;
use Core::Utils qw(
    encode_json
);

my $user = SHM->new( user_id => 40092 );

subtest 'Test encode_json()' => sub {
    my $s = 'привет';
    utf8::decode( $s );
    is( $s ne 'привет', 1 );

    my $data = {
        perl_str => $s,
        str => 'привет',
    };

    is( utf8::is_utf8( $data->{perl_str}), 1);
    is( utf8::is_utf8( $data->{str}), '');

    my $json = encode_json( $data );
    is( $json, '{"perl_str":"привет","str":"привет"}' );
};

done_testing();
