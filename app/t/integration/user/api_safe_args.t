use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

is( $user->get_discount, '0', 'Get user discount' );
is( $user->get_phone, undef, 'Get user phone' );

$user->api('set',
    discount => 13,
    phone => '+7 123 456-78-90',
    admin => 0,
);

is( $user->get_discount, '0', 'Get user discount after set' );
is( $user->get_phone, '+7 123 456-78-90', 'Get user phone' );

done_testing();
