use strict;
use warnings;

use v5.14;
use Test::More;
use Test::MockTime;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );
use Core::Const;

$ENV{SHM_TEST} = 1;

use SHM;
my $user = SHM->new( user_id => 40092 );

my $service = get_service('service')->add(
    name => 'test service 1',
    category => 'test-category-1',
    cost => 200,
    allow_to_order => 1,
);

my $service_next = get_service('service')->add(
    name => 'test service 2',
    category => 'test-category-1',
    cost => 100,
    allow_to_order => 1,
    next => 1,
);

# Отдельная услуга, у которой администратор явно разрешил неполный период.
# Используется только в тестах на allow_partial_period, чтобы не путать
# с $service_next, где этот флаг не установлен (используется для проверки
# запрета).
my $service_partial = get_service('service')->add(
    name => 'test service partial (allow_partial_period=1)',
    category => 'test-category-1',
    cost => 100,
    allow_to_order => 1,
    config => { allow_partial_period => 1 },
);

subtest 'Check WAIT_FOR_PAY -> WAIT_FOR_PAY' => sub {
    $user->set( balance => 10, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_WAIT_FOR_PAY);
    is( $us->withdraw->total, $service->cost );
    is ( $us->get_next, 0 );

    $us->change( service_id => $service_next->id );

    is ( $us->service_id, $service_next->id );
    is ( $us->status, STATUS_WAIT_FOR_PAY);
    is( $us->withdraw->total, $service_next->cost );
    is ( $us->get_next, 1 );
};

subtest 'Check WAIT_FOR_PAY -> ACTIVE' => sub {
    $user->set( balance => 100, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_WAIT_FOR_PAY);
    is( $us->withdraw->total, $service->cost );

    $us->change( service_id => $service_next->id );

    is ( $us->service_id, $service_next->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service_next->cost );
};

subtest 'Check ACTIVE -> BLOCK -> ACTIVE' => sub {
    $user->set( balance => 200, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service->cost );
    is ( $user->balance, 0 );

    $user->set( balance => -200, credit => 0 );
    $us->change( service_id => $service_next->id );

    is ( $us->service_id, $service_next->id );
    is ( $us->status, STATUS_BLOCK);
    is( $us->withdraw->total, $service_next->cost );
    is ( $user->balance, 0 );

    $user->set( balance => 200, credit => 0 );
    $us->change( service_id => $service->id );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service->cost );
    is ( $user->balance, 0 );
};

subtest 'Check ACTIVE -> ACTIVE' => sub {
    $user->set( balance => 200, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is ( $us->service_id, $service->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service->cost );
    is ( $user->balance, 0 );

    $us->change( service_id => $service_next->id );

    is ( $us->service_id, $service_next->id );
    is ( $us->status, STATUS_ACTIVE);
    is( $us->withdraw->total, $service_next->cost );
    is ( $user->balance, 100 );
};

subtest 'Check WAIT_FOR_PAY -> ACTIVE with allow_partial_period' => sub {
    $user->set( balance => 50, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is( $us->service_id, $service->id );
    is( $us->status, STATUS_WAIT_FOR_PAY );

    $us->change( service_id => $service_partial->id, allow_partial_period => 1 );

    is( $us->service_id, $service_partial->id );
    is( $us->status, STATUS_ACTIVE );
    is( $us->withdraw->total, 50 );
    isnt( $us->withdraw->months, '0.0000' );
    is( $user->balance, 0 );
};

subtest 'Check WAIT_FOR_PAY -> ACTIVE when allow_partial_period is requested manually (by param)' => sub {
    $user->set( balance => 50, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is( $us->service_id, $service->id );
    is( $us->status, STATUS_WAIT_FOR_PAY );

    # $service_next не разрешает allow_partial_period в своих настройках,
    # но клиент (например, через /admin/user/service/change) может явно
    # запросить неполный период параметром - такой запрос должен быть выполнен.
    $us->change( service_id => $service_next->id, allow_partial_period => 1 );

    is( $us->service_id, $service_next->id );
    is( $us->status, STATUS_ACTIVE, 'Service is activated on partial balance' );
    is( $us->withdraw->total, 50, 'Withdraw equals the available balance' );
    is( $user->balance, 0, 'Balance is fully consumed' );
};

subtest 'Check BLOCK -> ACTIVE with allow_partial_period' => sub {
    $user->set( balance => 200, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is( $us->status, STATUS_ACTIVE );
    is( $user->balance, 0 );

    $user->set( balance => -200, credit => 0 );
    $us->change( service_id => $service_next->id );

    is( $us->service_id, $service_next->id );
    is( $us->status, STATUS_BLOCK );
    is( $us->withdraw->total, $service_next->cost );
    is( $user->balance, 0 );

    $user->set( balance => 50, credit => 0 );
    $us->change( service_id => $service_partial->id, allow_partial_period => 1 );

    is( $us->service_id, $service_partial->id );
    is( $us->status, STATUS_ACTIVE );
    is( $us->withdraw->total, 50 );
    isnt( $us->withdraw->months, '0.0000' );
    is( $user->balance, 0 );
};

subtest 'Check BLOCK -> ACTIVE when allow_partial_period is requested manually (by param)' => sub {
    $user->set( balance => 200, credit => 0 );

    my $us = $service->reg(
        service_id => $service->id,
    );

    is( $us->status, STATUS_ACTIVE );
    is( $user->balance, 0 );

    $user->set( balance => -200, credit => 0 );
    $us->change( service_id => $service_next->id );

    is( $us->service_id, $service_next->id );
    is( $us->status, STATUS_BLOCK );
    is( $us->withdraw->total, $service_next->cost );
    is( $user->balance, 0 );

    $user->set( balance => 50, credit => 0 );
    # $service_next не разрешает allow_partial_period в своих настройках, но
    # явный клиентский параметр должен быть выполнен (manual override).
    $us->change( service_id => $service_next->id, allow_partial_period => 1 );

    is( $us->service_id, $service_next->id );
    is( $us->status, STATUS_ACTIVE, 'Service is activated by manual partial period request' );
    is( $us->withdraw->total, 50, 'Withdraw equals the available balance' );
    is( $user->balance, 0, 'Balance is fully consumed' );
};

subtest 'Check ACTIVE -> ACTIVE partial period with allow_partial_period' => sub {
    Test::MockTime::set_fixed_time('2019-10-01T00:00:00Z');

    my $partial_service = get_service('service')->add(
        name          => 'test partial period service',
        category      => 'test',
        cost          => 100,
        period        => 1,
        allow_to_order => 1,
        no_discount   => 1,
        config        => { allow_partial_period => 1 },
    );

    $user->set( balance => 100, credit => 0 );

    my $us = $partial_service->reg(
        service_id => $partial_service->id,
    );

    is( $us->status, STATUS_ACTIVE, 'Service is active after creation' );
    is( $user->balance, 0,          'Balance fully consumed after creation' );

    Test::MockTime::set_fixed_time('2019-11-02T00:00:00Z');
    $user->set( balance => 50, credit => 0 );

    $us->change( service_id => $partial_service->id, allow_partial_period => 1 );

    is( $us->status, STATUS_ACTIVE,             'Service stays active after partial renewal' );
    is( $us->withdraw->total, 50,               'Withdraw total equals available balance' );
    isnt( $us->withdraw->months, '0.0000',      'Withdraw has partial months' );
    is( $user->balance, 0,                      'Balance fully consumed after partial renewal' );

    Test::MockTime::restore_time();
};

subtest 'Check ACTIVE -> ACTIVE renewal when allow_partial_period is requested manually (by param)' => sub {
    Test::MockTime::set_fixed_time('2019-10-01T00:00:00Z');

    my $no_partial_service = get_service('service')->add(
        name          => 'test no-partial period service',
        category      => 'test',
        cost          => 100,
        period        => 1,
        allow_to_order => 1,
        no_discount   => 1,
    );

    $user->set( balance => 100, credit => 0 );

    my $us = $no_partial_service->reg(
        service_id => $no_partial_service->id,
    );

    is( $us->status, STATUS_ACTIVE, 'Service is active after creation' );
    is( $user->balance, 0,          'Balance fully consumed after creation' );

    Test::MockTime::set_fixed_time('2019-11-02T00:00:00Z');
    $user->set( balance => 50, credit => 0 );

    # Тариф не разрешает allow_partial_period в своих настройках, но явный
    # клиентский параметр должен быть выполнен (manual override, например
    # через /admin/user/service/change).
    $us->change( service_id => $no_partial_service->id, allow_partial_period => 1 );

    is( $us->status, STATUS_ACTIVE,         'Service stays active after manual partial renewal' );
    is( $us->withdraw->total, 50,           'Withdraw total equals available balance' );
    isnt( $us->withdraw->months, '0.0000',  'Withdraw has partial months' );
    is( $user->balance, 0,                  'Balance fully consumed after partial renewal' );

    Test::MockTime::restore_time();
};

subtest 'Check ACTIVE -> BLOCK when renewal with allow_partial_period = 0' => sub {
    Test::MockTime::set_fixed_time('2019-10-01T00:00:00Z');

    my $no_partial_service = get_service('service')->add(
        name          => 'test no-partial period service (explicit 0)',
        category      => 'test',
        cost          => 100,
        period        => 1,
        allow_to_order => 1,
        no_discount   => 1,
    );

    $user->set( balance => 100, credit => 0 );

    my $us = $no_partial_service->reg(
        service_id => $no_partial_service->id,
    );

    is( $us->status, STATUS_ACTIVE, 'Service is active after creation' );
    is( $user->balance, 0,          'Balance fully consumed after creation' );

    Test::MockTime::set_fixed_time('2019-11-02T00:00:00Z');
    $user->set( balance => 50, credit => 0 );

    # Тариф не разрешает allow_partial_period, и клиент явно передал 0 -
    # услуга блокируется как при обычном продлении без достаточных средств.
    $us->change( service_id => $no_partial_service->id, allow_partial_period => 0 );

    is( $us->status, STATUS_BLOCK,              'Service is blocked, partial renewal was not requested' );
    is( $us->withdraw->total, $no_partial_service->cost, 'Withdraw is for the full cost, not the available balance' );
    is( $user->balance, 50,                     'Balance is not touched' );

    Test::MockTime::restore_time();
};

done_testing();

