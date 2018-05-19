use v5.14;

use Test::More;
use Data::Dumper;

use POSIX qw(tzset);
$ENV{TZ} = 'Europe/Moscow';
tzset;

use Test::MockTime;
Test::MockTime::set_fixed_time('2016-12-31T21:00:00Z'); # Sun Jan  1 00:00:00 2017

use base qw( Core::System::Service );
use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;

use SHM;
my $srv = SHM->new( user_id => 40092 )->services;

use Core::Billing;

my $us = create_service( service_id => 4, cost => 1004.129, months => 0.01 );
my $ret = $srv->id( $us->id )->with('withdraws')->get;

is( $ret->{ $us->id }->{expired}, '2017-01-01 23:59:59', 'Check expired service for months = 0.01 (one day)' );
is( $ret->{ $us->id }->{service_id}, 4, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{months}, 0.01, 'Check months for one day' );
is( $ret->{ $us->id }->{withdraws}->{total}, 32.39, 'Check total for one day' );


my $us = create_service( service_id => 1, cost => 1000, months => 1 );
my $ret = $srv->id( $us->id )->with('withdraws')->get;

is( $ret->{ $us->id }->{expired}, '2017-01-31 23:59:59', 'Check expired service for months = 1 (one month)' );
is( $ret->{ $us->id }->{service_id}, 1, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{total}, 1000, 'Check total for one month' );

# Check create service for 2.01 month
my $us = create_service( service_id => 1, cost => 1000, months => 2.01 );
my $ret = $srv->id( $us->id )->with('withdraws')->get;

is( $ret->{ $us->id }->{expired}, '2017-03-01 23:59:59', 'Check expired service for months = 2.01' );
is( $ret->{ $us->id }->{service_id}, 1, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{total}, 2032.26, 'Check total for 2.01 month' );

# Check create service with discount
my $us = create_service( service_id => 1, cost => 100, months => 4 );
my $ret = $srv->id( $us->id )->with('withdraws')->get;

is( $ret->{ $us->id }->{expired}, '2017-04-30 23:59:59', 'Check expired service for months = 4' );
is( $ret->{ $us->id }->{service_id}, 1, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{discount}, 10, 'Check discont for 4 months' );
is( $ret->{ $us->id }->{withdraws}->{total}, 360, 'Check total for 4 months with discount' );

# Check create domain service
my $us = create_service( service_id => 11, cost => 1000 );

my $ret = $srv->id( $us->id )->with('withdraws')->get;
is( $ret->{ $us->id }->{expired}, '2017-12-31 23:59:59', 'Check expired service for domain' );
is( $ret->{ $us->id }->{service_id}, 11, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{discount}, 0, 'Check total for domain' );
is( $ret->{ $us->id }->{withdraws}->{total}, 1000, 'Check total for domain' );
is( $ret->{ $us->id }->{withdraws}->{months}, 12, 'Check months for domain' );

done_testing();

