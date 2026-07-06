use v5.14;

use Test::More;
use Test::MockTime;
use POSIX qw(tzset);

use Core::Billing;
use Core::Const;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;

my $user = SHM->new( user_id => 40092 );

$ENV{TZ} = 'Europe/London';
tzset;

Test::MockTime::set_fixed_time('2019-01-01T00:00:00Z');

# ── is_pay: нормальная оплата ─────────────────────────────────────────────────

subtest 'is_pay: normal payment deducts balance and marks withdraw as paid' => sub {
    $user->set( balance => 500, bonus => 0, credit => 0 );

    my $si = get_service('service')->add(
        name        => 'is_pay basic test',
        cost        => 100,
        category    => 'is_pay_basic',
        period      => 1,
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id );

    is( $us->is_paid,         1,   'service is paid after creation' );
    is( $user->get_balance,   400, 'balance reduced by service cost' );
    ok( $us->withdraw->get_withdraw_date, 'withdraw_date is set' );
};

# ── is_pay: уже оплаченный withdraw не списывает повторно ─────────────────────

subtest 'is_pay: already-paid withdraw not charged twice' => sub {
    $user->set( balance => 500, bonus => 0, credit => 0 );

    my $si = get_service('service')->add(
        name        => 'is_pay no-double test',
        cost        => 100,
        category    => 'is_pay_no_dbl',
        period      => 1,
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id );
    is( $user->get_balance, 400, 'balance after first payment' );

    # Прямой вызов is_pay на уже оплаченной услуге: withdraw_date != NULL → return 1
    my $result = Core::Billing::is_pay($us);
    is( $result,            1,   'is_pay returns 1 for already-paid service' );
    is( $user->get_balance, 400, 'balance NOT changed on repeated call' );
};

# ── is_pay: второй платёж читает актуальный баланс ───────────────────────────

subtest 'is_pay: sequential payments reduce balance correctly via user reload' => sub {
    $user->set( balance => 200, bonus => 0, credit => 0 );

    my $si = get_service('service')->add(
        name        => 'is_pay reload test',
        cost        => 100,
        category    => 'is_pay_reload',
        period      => 1,
        no_discount => 1,
    );

    # Первая оплата: читает баланс=200, списывает 100
    my $us1 = create_service( service_id => $si->id );
    is( $user->get_balance, 100, 'balance = 100 after first payment' );

    # Вторая оплата: user->reload в is_pay читает актуальный баланс=100, списывает ещё 100
    my $us2 = create_service( service_id => $si->id );
    is( $user->get_balance, 0, 'balance = 0 after second payment (uses reloaded balance)' );
};

# ── is_pay: limit_bonus_percent корректно делит платёж ───────────────────────

subtest 'is_pay: limit_bonus_percent splits payment into bonus and cash correctly' => sub {
    $user->set( balance => 500, bonus => 200, credit => 0 );

    my $si = get_service('service')->add(
        name        => 'is_pay bonus limit',
        cost        => 100,
        category    => 'is_pay_bonus',
        period      => 1,
        no_discount => 1,
        config      => { limit_bonus_percent => 50 },
    );

    my $us = create_service( service_id => $si->id );

    is( $us->is_paid,                 1,   'service is paid' );
    is( $us->withdraw->get_bonus,     50,  'withdraw.bonus = 50 (50% of cost)' );
    is( $us->withdraw->get_total,     50,  'withdraw.total = 50 (remaining cash)' );
    is( $user->get_bonus,             150, 'user bonus reduced by 50' );
    is( $user->get_balance,           450, 'user balance reduced by 50' );
};

# ── Withdraw::api_set: корректная корректировка баланса при изменении стоимости

subtest 'api_set: cost increase charges correct delta — bonus not double-subtracted' => sub {
    # Сценарий: сервис 100 руб., limit_bonus = 50% → оплачено: 50 бонус + 50 деньги.
    # Администратор поднимает стоимость до 200.
    # Новый total = 200 - 50(старый бонус) = 150.
    # Корректировка баланса = старый cash(50) - новый total(150) = -100 (доплата 100).
    # Старая формула с багом давала: 50 - (150 - 50) = -50 (доплата только 50).

    $user->set( balance => 1000, bonus => 200, credit => 0 );

    my $si = get_service('service')->add(
        name        => 'api_set increase',
        cost        => 100,
        category    => 'api_increase',
        period      => 1,
        no_discount => 1,
        config      => { limit_bonus_percent => 50 },
    );

    my $us = create_service( service_id => $si->id );
    # Paid: 50 bonus + 50 cash
    is( $user->get_balance, 950, 'balance after initial payment' );
    is( $user->get_bonus,   150, 'bonus after initial payment' );
    is( $us->withdraw->get_total, 50, 'wd.total = 50 (cash paid)' );
    is( $us->withdraw->get_bonus, 50, 'wd.bonus = 50 (bonus paid)' );

    # Администратор поднимает стоимость до 200
    $us->withdraw->api_set(
        cost            => 200,
        service_id      => $si->id,
        user_service_id => $us->id,
    );

    is( $user->get_balance, 850, 'balance charged by correct delta of 100 (not 50)' );
    is( $user->get_bonus,   150, 'bonus unchanged after cost change' );
};

subtest 'api_set: cost decrease refunds correct delta — bonus not double-subtracted' => sub {
    # Сценарий: сервис 100 руб., limit_bonus = 50% → оплачено: 50 бонус + 50 деньги.
    # Администратор снижает стоимость до 60.
    # Новый total = 60 - 50(старый бонус) = 10.
    # Корректировка баланса = старый cash(50) - новый total(10) = +40 (возврат 40).
    # Старая формула с багом давала: 50 - (10 - 50) = +90 (возврат 90).

    $user->set( balance => 1000, bonus => 200, credit => 0 );

    my $si = get_service('service')->add(
        name        => 'api_set decrease',
        cost        => 100,
        category    => 'api_decrease',
        period      => 1,
        no_discount => 1,
        config      => { limit_bonus_percent => 50 },
    );

    my $us = create_service( service_id => $si->id );
    # Paid: 50 bonus + 50 cash → balance=950, bonus=150
    is( $user->get_balance, 950, 'balance after initial payment' );

    # Администратор снижает стоимость до 60
    $us->withdraw->api_set(
        cost            => 60,
        service_id      => $si->id,
        user_service_id => $us->id,
    );

    # Refund: 40 (not 90 as buggy formula would give)
    is( $user->get_balance, 990, 'balance refunded correct delta of 40 (not 90)' );
    is( $user->get_bonus,   150, 'bonus unchanged after cost change' );
};

subtest 'api_set: no bonus — balance adjustment equals cost difference' => sub {
    # Без бонусов обе формулы дают одинаковый результат.
    # Этот тест гарантирует, что исправление не сломало случай без бонусов.

    $user->set( balance => 1000, bonus => 0, credit => 0 );

    my $si = get_service('service')->add(
        name        => 'api_set no bonus',
        cost        => 100,
        category    => 'api_no_bonus',
        period      => 1,
        no_discount => 1,
    );

    my $us = create_service( service_id => $si->id );
    is( $user->get_balance, 900, 'balance after initial payment of 100' );

    # Поднимаем до 150 → доплата 50
    $us->withdraw->api_set(
        cost            => 150,
        service_id      => $si->id,
        user_service_id => $us->id,
    );

    is( $user->get_balance, 850, 'balance charged correct delta of 50 on cost increase' );
};

done_testing();
