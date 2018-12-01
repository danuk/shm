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

my $key_file = "$ENV{HOME}/.ssh/ssm.key";
my $fingerprint = '2048 MD5:b9:4f:80:30:b7:a7:90:97:6f:2a:50:1a:74:65:dc:68 ansible-generated on shm (RSA)';

my $id = $obj->add(
    name => 'test',
    private_key => read_file( $key_file ),
);

my $data = $obj->id( $id )->get;

cmp_deeply( $data,
    {
        id => $id,
        name => 'test',
        user_id => 40092,
        fingerprint => $fingerprint,
        private_key => ignore(),
        public_key => undef,
    },
    'Check new key'
);

done_testing();
