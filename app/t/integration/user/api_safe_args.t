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
is( $user->get_phone, '71234567890', 'Get user phone (digits only)' );

$user->api('set', phone => '+7 123 456-78-90', admin => 0);
is( $user->get_phone, '71234567890', 'Setting the same phone again is a no-op' );

$user->api('set', phone => '8 (800) 555-35-35', admin => 0);
is(
    join( ',', sort split( /, /, $user->get_phone ) ),
    join( ',', sort qw( 71234567890 88005553535 ) ),
    'New phone is added without removing the existing one',
);

done_testing();
