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
$ENV{TZ} = 'Europe/London'; #UTC+0
tzset;

$ENV{SHM_TEST} = 1;

SHM->new( user_id => 40092 );

my $spool = get_service('spool');
my $user = get_service('user');
my $us;

subtest 'Prepare user for test billing' => sub {
    $user->set( balance => 2000, credit => 0, discount => 0 );
    is( $user->get_balance, 2000, 'Check user balance');
};

# Now date
Test::MockTime::set_fixed_time('2017-01-01T00:00:00Z');

subtest 'Check create service' => sub {
    $us = create_service( service_id => 4, cost => 1000, months => 1 );

    is( $us->get_expired, '2017-01-31 23:59:59', 'Check expired date after create new service' );
    is( $us->get_status, $STATUS_PROGRESS, 'Check status of new service' );
    is( $user->get_balance, 1000, 'Check user balance');

    #    my @spool_list = $spool->list( where => { user_service_id => $us->id } );
    #
    #    my @spool_categories = map $_->{category}, @spool_list;
    #    cmp_deeply( [ @spool_categories ], bag('web_tariff','web','mysql'), 'Check spool commands for create all services' );
    #
    #    $spool->_delete( where => { event => 'create' } );
};

# One month later...
Test::MockTime::set_fixed_time('2017-02-01T00:00:00Z');

subtest 'Try process service for not active services' => sub {
    my $ret = process_service( $us );

    is( $ret, 0, 'Check status for inactive service' );
    is( $us->get_expired, '2017-01-31 23:59:59', 'Check expired date after not prolongate' );
};

# Activate service
set_service_status_deeply( $us, $STATUS_ACTIVE );

# One month and one day later...
Test::MockTime::set_fixed_time('2017-02-05T00:00:00Z');

subtest 'Check expired service and try plolongate' => sub {
    my $ret = process_service( $us );
    is( $ret, 1, 'Check status for active service' );

    is( $us->get_expired, '2017-02-28 23:59:57', 'Check expired date after prolongate' );

    my @all_wd = get_service('wd')->list( where => { user_service_id => $us->id } );

    cmp_deeply( \@all_wd, bag(
		{
			'withdraw_id' => ignore(),
			'user_service_id' => $us->id,
			'create_date' 	=> '2017-01-01 00:00:00',
			'withdraw_date' => '2017-01-01 00:00:00',
			'end_date' 		=> '2017-01-31 23:59:59',
			'user_id' => 40092,
			'service_id' => 4,
			'cost' => 1000,
			'qnt' => 1,
			'months' => 1,
			'discount' => 0,
			'bonus' => 0,
			'total' => 1000,
		},
		{
			'withdraw_id' => ignore(),
			'user_service_id' => $us->id,
			'create_date' 	=> '2017-02-05 00:00:00',
			'withdraw_date' => '2017-02-05 00:00:00',
			'end_date' 		=> '2017-02-28 23:59:57',
			'user_id' => 40092,
			'service_id' => 4,
			'cost' => 1000,
			'qnt' => 1,
			'months' => 1,
			'discount' => 0,
			'bonus' => 0,
			'total' => 1000,
		},
    ),'Check all withdraws for service');

    is( $us->get_status, $STATUS_PROGRESS, 'Check status of prolong service' );
    is( $user->get_balance, 0, 'Check user balance');

    #    my @spool_list = $spool->list( where => { event => 'prolongate' } );
    #    my @spool_categories = map $_->{category}, @spool_list;
    #    cmp_deeply( [ @spool_categories ], bag('web_tariff'), 'Check spool commands for prolongate services' );
    #    $spool->_delete( where => { event => 'prolongate' } );
 
    set_service_status_deeply( $us, $STATUS_ACTIVE );
};

# Two month later...
Test::MockTime::set_fixed_time('2017-03-01T00:00:00Z');

subtest 'Try prolongate service without have money' => sub {
    my $ret = process_service( $us );
    is( $ret, 0, 'Check ret status of process_service' );

    is( $us->get_expired, '2017-02-28 23:59:57', 'Check expired date after prolongate' );
    is( $us->get_status, $STATUS_PROGRESS, 'Check status of prolong service' );
    is( $user->get_balance, 0, 'Check user balance');
    
    my @all_wd = get_service('wd')->list( where => { user_service_id => $us->id } );
 	cmp_deeply( $all_wd[-1], {
			'withdraw_id' => $us->get_withdraw_id,
			'user_service_id' => $us->id,
			'create_date'	=> '2017-03-01 00:00:00',
			'withdraw_date' =>	undef, 
			'end_date' 		=> 	undef,
			'user_id' => 40092,
			'service_id' => 4,
			'cost' => 1000,
			'qnt' => 1,
			'months' => 1,
			'discount' => 0,
			'bonus' => 0,
			'total' => 1000,
	}, 'Check withdraw');

#    my @spool_list = $spool->list( where => { event => 'block' } );
#    my @spool_categories = map $_->{category}, @spool_list;
#    cmp_deeply( [ @spool_categories ], bag('web_tariff'), 'Check spool commands for prolongate services' );
#	$spool->_delete( where => { event => 'block' } );

    set_service_status_deeply( $us, $STATUS_BLOCK );
};

subtest 'Try prolongate blocked service without have money' => sub {
    my $ret = process_service( $us );
    is( $ret, 0, 'Check ret status of process_service' );

	my @spool = $spool->list();
	is( scalar @spool, 0, 'Check spool for empty' );
};

# 2 day later after blocking service
Test::MockTime::set_fixed_time('2017-03-02T12:00:00Z');

subtest 'Try prolongate blocked service' => sub {
    $user->set( balance => 2000, credit => 0, discount => 0 );

    my $withdraw_id = $us->get_withdraw_id;

    my $ret = process_service( $us );
    is( $ret, 1, 'Check ret status of process_service' );

    is( int($withdraw_id==$us->get_withdraw_id), 1, 'Check use current withdraw (no create new)' );

    my @all_wd = get_service('wd')->list( where => { user_service_id => $us->id } );
 	cmp_deeply( $all_wd[-1], {
			'withdraw_id' => $withdraw_id,
			'user_service_id' => $us->id,
			'create_date'	=> '2017-03-01 00:00:00',
			'withdraw_date' => '2017-03-02 12:00:00', 
			'end_date' 		=> '2017-04-02 10:50:18',
			'user_id' => 40092,
			'service_id' => 4,
			'cost' => 1000,
			'qnt' => 1,
			'months' => 1,
			'discount' => 0,
			'bonus' => 0,
			'total' => 1000,
	}, 'Check withdraw' );

    is( $us->get_expired, $us->withdraws->res->{end_date}, 'Check expired date after prolongate' );
    is( $user->get_balance, 1000, 'Check user balance');

    #    my @spool_list = $spool->list( where => { event => 'prolongate' } );
    #    my @spool_categories = map $_->{category}, @spool_list;
    #    cmp_deeply( [ @spool_categories ], bag('web_tariff'), 'Check spool commands for prolongate services' );
    #    $spool->_delete( where => { event => 'prolongate' } );

    set_service_status_deeply( $us, $STATUS_ACTIVE );
};

done_testing();
exit 0;

sub set_service_status_deeply {
    my $service = shift;
    my $status = shift || 2;

    $service->set( status => $status );

    for ( keys %{ $service->children } ) {
        get_service('us', _id => $_ )->set( status => $status );
    }
}
