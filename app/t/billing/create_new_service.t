use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

use POSIX qw(tzset);
$ENV{TZ} = 'Europe/Moscow';
tzset;

use Test::MockTime;
Test::MockTime::set_fixed_time('2016-12-31T21:00:00Z'); # Sun Jan  1 00:00:00 2017

use Core::Const;
use base qw( Core::System::Service );
use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;

use SHM;
my $srv = SHM->new( user_id => 40092 )->services;

use Core::Billing;

my $us = create_service( service_id => 4, cost => 1004.129, months => 0.01 );
my $ret = $srv->id( $us->id )->with('withdraws')->get;

is( $ret->{ $us->id }->{expire}, '2017-01-01 23:59:59', 'Check expire service for months = 0.01 (one day)' );
is( $ret->{ $us->id }->{service_id}, 4, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{months}, 0.01, 'Check months for one day' );
is( $ret->{ $us->id }->{withdraws}->{total}, 32.39, 'Check total for one day' );


my $us = create_service( service_id => 1, cost => 1000, months => 1 );
my $ret = $srv->id( $us->id )->with('withdraws')->get;

is( $ret->{ $us->id }->{expire}, '2017-01-31 23:59:59', 'Check expire service for months = 1 (one month)' );
is( $ret->{ $us->id }->{service_id}, 1, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{total}, 1000, 'Check total for one month' );

# Check create service for 2.01 month
my $us = create_service( service_id => 1, cost => 1000, months => 2.01 );
my $ret = $srv->id( $us->id )->with('withdraws')->get;

is( $ret->{ $us->id }->{expire}, '2017-03-01 23:59:59', 'Check expire service for months = 2.01' );
is( $ret->{ $us->id }->{service_id}, 1, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{total}, 2032.26, 'Check total for 2.01 month' );

# Check create service with discount
my $us = create_service( service_id => 1, cost => 100, months => 4 );
my $ret = $srv->id( $us->id )->with('withdraws')->get;

is( $ret->{ $us->id }->{expire}, '2017-04-30 23:59:59', 'Check expire service for months = 4' );
is( $ret->{ $us->id }->{service_id}, 1, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{discount}, 10, 'Check discont for 4 months' );
is( $ret->{ $us->id }->{withdraws}->{total}, 360, 'Check total for 4 months with discount' );

# Check create domain service
my $us = create_service( service_id => 11, cost => 1000, months => 12 );

my $ret = $srv->id( $us->id )->with('withdraws')->get;
is( $ret->{ $us->id }->{expire}, '2017-12-31 23:59:59', 'Check expire service for domain' );
is( $ret->{ $us->id }->{service_id}, 11, 'Check service_id for new service' );
is( $ret->{ $us->id }->{withdraws}->{discount}, 0, 'Check total for domain' );
is( $ret->{ $us->id }->{withdraws}->{total}, 1000, 'Check total for domain' );
is( $ret->{ $us->id }->{withdraws}->{months}, 12, 'Check months for domain' );

subtest 'Check create service with period' => sub {
    my $si = get_service('service')->add( name => 'TEST', cost => 123, category => 'new', period => 3 );

    my $us = create_service( service_id => $si->get_service_id );

    cmp_deeply( scalar $us->get, superhashof(
        {
            status => 'ACTIVE',
            created => '2017-01-01 00:00:00',
            expire => '2017-03-31 23:59:59',
            parent => undef,
            settings => undef,
            service_id => $si->get_service_id,
            next => 0,
            auto_bill => 1,
            user_service_id => ignore(),
            withdraw_id => ignore(),
            user_id => 40092,
        },
    ));
};

subtest 'Check `pay_always` flag' => sub {
    my $si = get_service('service')->add( name => 'TEST', cost => 1, category => 'new', period => 1, pay_always => 0 );

    my $parent_us = create_service( service_id => $si->id );
    is( $parent_us->is_paid, 1 );

    my $sub1_us = create_service( service_id => $si->id, parent => $parent_us->id );
    is( $sub1_us->is_paid, 0 );

    $si->set( pay_always => 1 );
    my $sub2_us = create_service( service_id => $si->id, parent => $parent_us->id );
    is( $sub2_us->is_paid, 1 );
};

subtest 'Check set `end_date` via service.create' => sub {
    my $si = get_service('service')->add( name => 'TEST', cost => 1, category => 'new', period => 1, pay_always => 0, allow_to_order => 1 );
    my $manual_end_date = '2024-10-01 00:00:00';
    my $us = $si->reg(
        service_id => $si->id,
        end_date => $manual_end_date,
    );

    is ($us->expire, $manual_end_date );
};

done_testing();

