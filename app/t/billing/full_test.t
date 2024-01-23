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

my $user = SHM->new( user_id => 40092 );

$ENV{TZ} = 'Europe/London'; #UTC+0
tzset;

my $spool = get_service('spool');

my $t = get_service('Transport::Ssh');
no warnings 'once';
no warnings qw(redefine);
*Core::Transport::Ssh::exec = sub {
    my $self = shift;
    my %args = @_;

    return SUCCESS, {
        server => {
            id => $args{server_id},
            host => $args{host},
            port => $args{port},
            key_id => $args{key_id},
        },
        cmd => $args{cmd},
        ret_code => 0,
        pipeline_id => $args{pipeline_id},
    };
};

my $us;
my $user_services = get_service('UserService');

subtest 'Prepare user for test billing' => sub {
    $user->set( balance => 2000, credit => 0, discount => 0 );
    is( $user->get_balance, 2000, 'Check user balance');
};

# Now date
Test::MockTime::set_fixed_time('2017-01-01T00:00:00Z');

subtest 'Check create service' => sub {

    $us = create_service( service_id => 4, cost => 1000, months => 1 );

    is( $us->get_expire, '2017-01-31 23:59:59', 'Check expire date after create new service' );
    is( $user->get_balance, 1000, 'Check user balance after withdraw');

    is( $us->get_status, STATUS_PROGRESS, 'Check status of new service' );

    my $ch_by_service = chldrn_by_service( $us );

    cmp_deeply( $ch_by_service, {
        5 => superhashof( { status => STATUS_ACTIVE } ),
        8 => superhashof( { status => STATUS_ACTIVE } ),
        29 => superhashof( { status => STATUS_PROGRESS } ),
    }, 'Check children statuses' );

    my @spool_list = $spool->list();

    is ( scalar @spool_list, 1, 'Check count spool commands' );

    cmp_deeply ( $spool_list[0], superhashof({
        status => TASK_NEW,
        executed => undef,
        event => {
            id => ignore(),
            server_gid => 1,
            settings => {
                category => 'mysql',
                cmd => 'mysql create -a b_{{ us.id }} -b {{ us.settings.db.0.name }} -u {{ us.settings.db.0.login }} -p {{ us.settings.db.0.password }}'
            },
            name => 'create',
            title => 'Create mysql',
            kind => 'UserService'
        },
        settings => {
            user_service_id => $ch_by_service->{29}->{user_service_id},
        },
        delayed => 0,
    }), 'Check spool command' );

    $spool->process_all();

    my $mysql_server_id = $us->child_by_category('mysql')->settings->{server_id};
    is( $mysql_server_id == 1 || $mysql_server_id == 2, 1 );
    is( $us->get_status, STATUS_ACTIVE, 'Check status of service after the creation childs' );
};

# Half month later...
Test::MockTime::set_fixed_time('2017-01-15T05:06:13Z');

subtest 'Half month later. Try prolongate service' => sub {
    my $ret = $us->touch();

    is( $us->get_expire, '2017-01-31 23:59:59', 'Check expire date after not prolongate' );
    is( $user->get_balance, 1000, 'Check user balance after withdraw');

    cmp_deeply( chldrn_by_service( $us ), {
        5 => superhashof( { status => STATUS_ACTIVE } ),
        8 => superhashof( { status => STATUS_ACTIVE } ),
        29 => superhashof( { status => STATUS_ACTIVE } ),
    }, 'Check children statuses' );
};

# One month later...
Test::MockTime::set_fixed_time('2017-02-01T13:14:01Z');

subtest 'One month later. Prolongate service' => sub {
    my $ret = $us->touch();

    is( $us->get_expire, '2017-02-28 23:59:57', 'Check expire date after prolongate' );
    is( $user->get_balance, 0, 'Check user balance after withdraw');

    my @children = $us->children;
    my %ch_by_service = map { $_->{service_id} => $_ } @children;

    cmp_deeply( \%ch_by_service , {
        5 => superhashof( { status => STATUS_ACTIVE } ),
        8 => superhashof( { status => STATUS_ACTIVE } ),
        29 => superhashof( { status => STATUS_ACTIVE } ),
    }, 'Check children statuses' );

    my @all_wd = get_service('wd')->list( where => { user_service_id => $us->id } );

    cmp_deeply( \@all_wd, bag(
        {
            'withdraw_id' => ignore(),
            'user_service_id' => $us->id,
            'create_date'   => '2017-01-01 00:00:00',
            'withdraw_date' => '2017-01-01 00:00:00',
            'end_date'      => '2017-01-31 23:59:59',
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
            'create_date'   => '2017-02-01 13:14:01',
            'withdraw_date' => '2017-02-01 13:14:01',
            'end_date'      => '2017-02-28 23:59:57',
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
};

# Two month later...
Test::MockTime::set_fixed_time('2017-03-01T00:00:00Z');

subtest 'Try prolongate service without have money' => sub {
    my $ret = $us->touch();

    is( $us->get_expire, '2017-02-28 23:59:57', 'Check expire date after prolongate' );
    is( $user->get_balance, 0, 'Check user balance');

    is( $us->get_status, STATUS_PROGRESS, 'Check status of prolong service' );

    my @children = $us->children;
    my %ch_by_service = map { $_->{service_id} => $_ } @children;

    cmp_deeply( \%ch_by_service, {
        5 => superhashof( { status => STATUS_BLOCK } ),
        8 => superhashof( { status => STATUS_BLOCK } ),
        29 => superhashof( { status => STATUS_PROGRESS } ),
    }, 'Check children statuses' );

    my @all_wd = get_service('wd')->list( where => { user_service_id => $us->id } );
    cmp_deeply( $all_wd[-1], {
            'withdraw_id' => $us->get_withdraw_id,
            'user_service_id' => $us->id,
            'create_date'   => '2017-03-01 00:00:00',
            'withdraw_date' =>  undef,
            'end_date'      =>  undef,
            'user_id' => 40092,
            'service_id' => 4,
            'cost' => 1000,
            'qnt' => 1,
            'months' => 1,
            'discount' => 0,
            'bonus' => 0,
            'total' => 1000,
    }, 'Check withdraw');

    $spool->process_all();

    is( $us->get_status, STATUS_BLOCK, 'Check status of prolong service' );

    cmp_deeply( chldrn_by_service( $us ), {
        5 => superhashof( { status => STATUS_BLOCK } ),
        8 => superhashof( { status => STATUS_BLOCK } ),
        29 => superhashof( { status => STATUS_BLOCK } ),
    }, 'Check children statuses' );

    is( $us->get_status, STATUS_BLOCK, 'Check status of prolong service' );
};

subtest 'Try prolongate blocked service without have money' => sub {
    my $ret = $us->touch();

    cmp_deeply( chldrn_by_service( $us ), {
        5 => superhashof( { status => STATUS_BLOCK } ),
        8 => superhashof( { status => STATUS_BLOCK } ),
        29 => superhashof( { status => STATUS_BLOCK } ),
    }, 'Check children statuses' );

    is( $us->get_status, STATUS_BLOCK, 'Check status of prolong service' );

    my @spool = $spool->list();
    is( scalar @spool, 0, 'Check spool for empty' );
};

# 2 day later after blocking service
Test::MockTime::set_fixed_time('2017-03-02T12:00:00Z');

subtest 'Try prolongate blocked service' => sub {
    $user->set( balance => 1000.03, credit => 0, discount => 0 );
    my $withdraw_id = $us->get_withdraw_id;
    $us->touch();

    is( int($withdraw_id==$us->get_withdraw_id), 1, 'Check use current withdraw (no create new)' );

    my @all_wd = get_service('wd')->list( where => { user_service_id => $us->id } );
    cmp_deeply( $all_wd[-1], {
            'withdraw_id' => $withdraw_id,
            'user_service_id' => $us->id,
            'create_date'   => '2017-03-01 00:00:00',
            'withdraw_date' => '2017-03-02 12:00:00',
            'end_date'      => '2017-04-02 10:50:18',
            'user_id' => 40092,
            'service_id' => 4,
            'cost' => 1000,
            'qnt' => 1,
            'months' => 1,
            'discount' => 0,
            'bonus' => 0,
            'total' => 1000,
    }, 'Check withdraw' );

    is( $us->get_expire, $us->withdraw->res->{end_date}, 'Check expire date after activate' );
    is( $user->get_balance, 0.03, 'Check user balance');

    cmp_deeply( chldrn_by_service( $us ), {
        5 => superhashof( { status => STATUS_ACTIVE } ),
        8 => superhashof( { status => STATUS_ACTIVE } ),
        29 => superhashof( { status => STATUS_PROGRESS } ),
    }, 'Check children statuses after unblock' );

    is( $us->get_status, STATUS_PROGRESS, 'Check status of prolong service after unblock' );

    $spool->process_all();

    is( $us->get_status, STATUS_ACTIVE, 'Check status of prolong service after unblock and spool' );

    cmp_deeply( chldrn_by_service( $us ), {
        5 => superhashof( { status => STATUS_ACTIVE } ),
        8 => superhashof( { status => STATUS_ACTIVE } ),
        29 => superhashof( { status => STATUS_ACTIVE } ),
    }, 'Check children statuses after spool executes' );

    is( $us->get_status, STATUS_ACTIVE, 'Check status of prolong service after spool executes' )
};

Test::MockTime::set_fixed_time('2018-01-01T00:00:00Z');
subtest 'Check create service without money' => sub {
    $us = create_service( service_id => 4, cost => 1000, months => 1 );

    is( $us->get_expire, undef, 'Check expire date after create new service' );
    is( $user->get_balance, 0.03, 'Check user balance after withdraw');

    is( $us->get_status, STATUS_WAIT_FOR_PAY, 'Check status of new service' );

    my $ch_by_service = chldrn_by_service( $us );

    cmp_deeply( $ch_by_service, {
        5 => superhashof( { status => STATUS_WAIT_FOR_PAY } ),
        8 => superhashof( { status => STATUS_WAIT_FOR_PAY } ),
        29 => superhashof( { status => STATUS_WAIT_FOR_PAY } ),
    }, 'Check children statuses' );

    my $withdraw_id = $us->get_withdraw_id;
    is( int($withdraw_id==$us->get_withdraw_id), 1, 'Check use current withdraw (no create new)' );

    my @all_wd = get_service('wd')->list( where => { user_service_id => $us->id } );
    cmp_deeply( $all_wd[-1], {
            'withdraw_id' => $withdraw_id,
            'user_service_id' => $us->id,
            'create_date'   => '2018-01-01 00:00:00',
            'withdraw_date' => undef,
            'end_date'      => undef,
            'user_id' => 40092,
            'service_id' => 4,
            'cost' => 1000,
            'qnt' => 1,
            'months' => 1,
            'discount' => 0,
            'bonus' => 0,
            'total' => 1000,
    }, 'Check withdraw' );

    my @spool_list = $spool->list();

    is ( scalar @spool_list, 0, 'Check count spool commands' );

    $user->set( balance => 1000, credit => 0, discount => 0 );
    $us->touch();

    is( $us->get_status, STATUS_PROGRESS, 'Check status of non payment service after payment' );

    cmp_deeply( chldrn_by_service( $us ), {
        5 => superhashof( { status => STATUS_ACTIVE } ),
        8 => superhashof( { status => STATUS_ACTIVE } ),
        29 => superhashof( { status => STATUS_PROGRESS } ),
    }, 'Check children statuses' );

    $spool->process_all();

    is( $us->get_status, STATUS_ACTIVE, 'Check status of non payment service after payment' );

    cmp_deeply( chldrn_by_service( $us ), {
        5 => superhashof( { status => STATUS_ACTIVE } ),
        8 => superhashof( { status => STATUS_ACTIVE } ),
        29 => superhashof( { status => STATUS_ACTIVE } ),
    }, 'Check children statuses' );
};

Test::MockTime::set_fixed_time('2018-01-15T00:00:00Z');
subtest 'Delete user service' => sub {

    $us->block();
    is( $us->get_status, STATUS_PROGRESS );

    $spool->process_all();
    is( $us->get_status, STATUS_BLOCK );

    $us->delete();
    is( $us->get_status, STATUS_PROGRESS );

    $spool->process_all();
    is( $us->get_status, STATUS_REMOVED );

    my $wd = $us->withdraw->get;
    cmp_deeply( $wd, {
            'withdraw_id' => $us->get_withdraw_id,
            'user_service_id' => $us->id,
            'create_date'   => '2018-01-01 00:00:00',
            'withdraw_date' => '2018-01-01 00:00:00',
            'end_date'      => '2018-01-15 00:00:00',
            'user_id' => 40092,
            'service_id' => 4,
            'cost' => 1000,
            'qnt' => 1,
            'months' => '0.14',
            'discount' => 0,
            'bonus' => 0,
            'total' => '451.61',
    }, 'Check withdraw' );
};

done_testing();
exit 0;

sub chldrn_by_service {
    my $self = shift;

    my %ret = map { $_->{service_id} => $_ } $self->children;
    return \%ret;
}
