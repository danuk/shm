use v5.14;

use Test::More;
use Test::MockTime;
use Test::Deep;
use Core::Billing;
use POSIX qw(tzset);
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(now);
use SHM;
my $user = SHM->new( user_id => 40092 );

$ENV{TZ} = 'Europe/London'; #UTC+0
tzset;


my $cost_sub_service = 10;
my $cost_service = 100;

my $sub_service = get_service('service')->add(
    name => 'paid sub service',
    cost => $cost_sub_service,
    period => 1,
    category => 'test',
    no_discount => 1,
);

my $service = get_service('service')->add(
    name => 'test service',
    cost => $cost_service,
    period => '1',
    category => 'test',
    no_discount => 1,
    is_composite => 1,
    allow_to_order => 1,
    children => [
        {
            service_id => $sub_service->id,
            qnt => 2,
        },
    ],
);

Test::MockTime::set_fixed_time('2019-04-01T00:00:00Z');

$user->set( balance => 100, credit => 0 );
my $us = create_service( service_id => $service->id );

my ( $child ) = $us->children;
my $us_child = get_service('us', _id => $child->{user_service_id} );

is( $us->wd_total_composite, 120 );

is( $user->get_balance, 100 );
is( $us->status, 'NOT PAID' );
is( $us_child->status, 'NOT PAID' );
is( $us->get_expire, undef);
is( $us_child->get_expire, undef);

$user->set( balance => 120, credit => 0 );
$us->touch();

is( $user->get_balance, 0 );
is( $us->status, 'ACTIVE' );
is( $us_child->status, 'ACTIVE' );
is( $us->get_expire, '2019-05-01 01:01:59');
is( $us_child->get_expire, '2019-05-01 01:01:59');


Test::MockTime::set_fixed_time('2019-05-03T00:00:00Z');
$us->touch();

is( $user->get_balance, 0 );
is( $us->get_expire, '2019-05-01 01:01:59');
is( $us_child->get_expire, '2019-05-01 01:01:59');
is( $us->status, 'BLOCK' );
is( $us_child->status, 'BLOCK' );

$user->set( balance => 120, credit => 0 );
$us->touch();

is( $user->get_balance, 0 );
is( $us->status, 'ACTIVE' );
is( $us_child->status, 'ACTIVE' );
is( $us->get_expire, '2019-06-02 23:25:08');
is( $us_child->get_expire, '2019-06-02 23:25:08');

is( get_service('service')->price_list->{ $service->id }->{cost}, 120 );

is( get_service('service')->price_list->{ $service->id }->{discount}, 0 );
is( get_service('service')->price_list->{ $service->id }->{real_cost}, 120 );

$user->set( discount => 10 );
is( get_service('service')->price_list->{ $service->id }->{discount}, 0 );
is( get_service('service')->price_list->{ $service->id }->{real_cost}, 120 );

$service->set( no_discount => 0);
is( get_service('service')->price_list->{ $service->id }->{discount}, 10 );
is( get_service('service')->price_list->{ $service->id }->{real_cost}, 108 );

$service->set( is_composite => 0 );
is( get_service('service')->price_list->{ $service->id }->{cost}, 100 );

done_testing();
