use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

is( $user->get_user_id, '40092', 'Get user_id' );
is( $user->get_discount, '0', 'Get user discount' );

$user->set( discount => 13 );
is( $user->get_discount, '13', 'Get user discount after set' );

my $who = get_service('user', _id => 108 );
is ( $who->get_user_id, 108 );

my @who_pays = $who->pays->list;
is ( scalar @who_pays, 0, 'Check pays for other user');

is( $user->id, 40092 );
is( $user->pays->user_id, 40092 );

my @pays = $user->pays->list;
is ( scalar @pays, 2, 'Check pays for main service');

subtest 'Try payment' => sub {
    is( $user->get_balance, -21.56, 'Check user balance before payment');

    $user->payment( money => 1000.03 );
    is( $user->get_balance, 978.47, 'Check user balance after payment');

    my $spool = get_service('spool');
    my ( $row ) = $spool->list;

    cmp_deeply( $row, superhashof({
          user_id => 40092,
          status => 'NEW',
          event => {
              name => 'PAYMENT',
              method => 'activate_services',
              kind => 'UserService',
              title => 'user payment'
          },
    }));

    $spool->_delete();
};

subtest 'Make payment with partner' => sub {
    $user->set( partner_id => 40094 );
    my $partner = $user->id( 40094 );
    is( $partner->get_bonus, 0 );

    $user->payment( money => 100 );
    is( $partner->get_bonus, 20 );

    my ( $user_spool ) = $user->srv('spool')->list;
    is( $user_spool->{user_id}, $user->id );
    is( $user_spool->{event}->{title}, 'user payment' );

    my ( $partner_spool ) = $partner->srv('spool')->list;
    is( $partner_spool->{user_id}, $partner->id );
    is( $partner_spool->{event}->{title}, 'user payment with bonuses' );
};

subtest 'Make payment with partner (personal income percent)' => sub {
    $user->set( partner_id => 40094 );
    my $partner = $user->id( 40094 );
    $partner->set_settings( { partner => { income_percent => 50 } } );

    is( $partner->get_bonus, 20 );
    $user->payment( money => 100 );
    is( $partner->get_bonus, 20 + 100/2 );

    my ( $user_spool ) = $user->srv('spool')->list;
    is( $user_spool->{user_id}, $user->id );
    is( $user_spool->{event}->{title}, 'user payment' );

    my ( $partner_spool ) = $partner->srv('spool')->list;
    is( $partner_spool->{user_id}, $partner->id );
    is( $partner_spool->{event}->{title}, 'user payment with bonuses' );
};

my %profile = $user->profile;

is $profile{email}, 'email@domain.ru', 'Check user profile';
is $user->emails, 'email@domain.ru', 'Check user email';

subtest 'Check user email by login' => sub {
    my $email = 'test@domain.ru';
    my $new_user_id = $user->reg(
        login => $email,
        password => 'testpassword',
    )->{user_id};

    my $new_user = $user->id( $new_user_id );

    is( $new_user->login, $email );
    is( $new_user->emails, $email );
};

subtest 'Check refferals count' => sub {
    is $user->referrals_count, 0;

    $user->id( 1 )->set( partner_id => 40092 );
    $user->id( 40094 )->set( partner_id => 40092 );
    is $user->referrals_count, 2;
};


done_testing();
