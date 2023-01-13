use v5.14;

use Test::More;
use Test::MockTime;
use Test::Deep;
use Core::Billing;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw( switch_user );
use SHM;
my $user = SHM->new( user_id => 40092 );

my $user1 = $user->add( login => 'user1', password => 'password' );
my $user2 = $user->add( login => 'user2', password => 'password', partner_id => $user1 );
my $user3 = $user->add( login => 'user3', password => 'password', partner_id => $user2 );

switch_user( $user3 );
Core::Billing::add_bonuses_for_partners( undef, 50 );

is( $user->id( $user1 )->get_bonus, 5 );
is( $user->id( $user2 )->get_bonus, 10 );
is( $user->id( $user3 )->get_bonus, 0 );

cmp_deeply ( $user->id( $user1 )->bonus->list, superhashof({
    id => ignore(),
    date => ignore(),
    user_id => $user1,
    bonus => 5,
    comment => {
        percent => 10,
        from_user_id => $user2,
    },
}));

cmp_deeply ( $user->id( $user2 )->bonus->list, superhashof({
    id => ignore(),
    date => ignore(),
    user_id => $user2,
    bonus => 10,
    comment => {
        percent => 20,
        from_user_id => $user3,
    },
}));

my @user3 = $user->id( $user3 )->bonus->list;
is( scalar @user3, 0 );

done_testing();
