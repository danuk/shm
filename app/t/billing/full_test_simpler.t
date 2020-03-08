use v5.14;

use Test::More;
use Test::Deep;
use Test::MockTime;
use Data::Dumper;
use base qw( Core::System::Service );
use SHM qw( get_service );
use Core::Billing;
use Core::Const;
use POSIX qw(tzset);

$ENV{SHM_TEST} = 1;

SHM->new( user_id => 40092 );

$ENV{TZ} = 'Europe/London'; #UTC+0
tzset;

my $spool = get_service('spool');
my $user = get_service('user');
my $us;
my $user_services = get_service('UserService');

# Switch billing to Simpler
my $config = get_service("config", _id => '_billing' );
$config->set( value => 'Simpler' );

subtest 'Prepare user for test billing' => sub {
    $user->set( balance => 2000, credit => 0, discount => 0 );
    is( $user->get_balance, 2000, 'Check user balance');
};

# Now date
Test::MockTime::set_fixed_time('2017-01-01T00:00:00Z');

subtest 'Check create service' => sub {

    $us = create_service( service_id => 4, cost => 1000, months => 1 );

    is( $us->get_expired, '2017-01-30 23:59:59', 'Check expired date after create new service' );
};

done_testing();
