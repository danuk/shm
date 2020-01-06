use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Billing;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $us = SHM->new( user_id => 40092 );

my $user = get_service('user');

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
              settings => {
                  kind => 'UserService',
                  method => 'activate_services'
              },
              kind => 'user',
              title => 'user payment'
          },
    }));

    #$spool->process_one;
    $spool->_delete();
};

my %profile = $user->profile;

is $profile{email}, 'email@domain.ru', 'Check user profile';
is scalar $user->emails, 1, 'Check user email';

done_testing();
