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
              method => 'activate_services',
              kind => 'UserService',
              title => 'user payment'
          },
    }));

    #$spool->process_one;
    $spool->_delete();
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

done_testing();
