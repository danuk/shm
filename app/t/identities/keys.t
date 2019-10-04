use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Utils qw/read_file/;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $obj = get_service('Identities');

my %key = $obj->generate_key_pair();

my $fingerprint = $key{fingerprint};

my $id = $obj->add(
    name => 'test',
    private_key => $key{private_key},
);

my $data = $obj->id( $id )->get;

$fingerprint =~s/\s+.*//;

my $fingerprint_generated = $data->{fingerprint};
$fingerprint_generated =~s/\s+.*//;

is( $fingerprint, $fingerprint_generated, 'Check fingerprint' );

cmp_deeply( $data,
    {
        id => $id,
        name => 'test',
        fingerprint => ignore(),
        private_key => $key{private_key},
        public_key => undef,
    },
    'Check new key'
);

done_testing();
