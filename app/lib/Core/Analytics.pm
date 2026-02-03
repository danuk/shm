package Core::Analytics;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw(now decode_json);

# Модуль аналитики биллинга
# Все методы используют кеширование для оптимизации

sub table { return 'users' };  # базовая таблица для init

sub structure {
    return {
        user_id => {
            type => 'number',
            key => 1,
        },
    };
}

# === ФИНАНСОВЫЙ АНАЛИЗ ===

# Общая выручка за период
sub revenue {
    my $self = shift;
    my %args = (
        start_date => undef,  # формат: 'YYYY-MM-DD'
        end_date => undef,
        months => undef,  # альтернатива start_date - последние N месяцев (0 = за всё время)
        no_cache => 0,
        @_,
    );

    # Формируем ключ кеша на основе months или дат
    my $cache_key;
    if (defined $args{months}) {
        $cache_key = sprintf('analytics_revenue_months_%d', $args{months});
        # Если указан months > 0, вычисляем start_date
        if (defined $args{months} && $args{months} > 0) {
            $args{start_date} = $self->dbh->selectrow_array(
                "SELECT DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL ? MONTH), '%Y-%m-%d')",
                undef, $args{months}
            );
        }
        # Если months = -1, это текущий месяц (с 1 числа по сегодня)
        elsif ($args{months} == -1) {
            $args{start_date} = $self->dbh->selectrow_array(
                "SELECT DATE_FORMAT(CURDATE(), '%Y-%m-01')"
            );
            $args{end_date} = $self->dbh->selectrow_array(
                "SELECT DATE_FORMAT(CURDATE(), '%Y-%m-%d')"
            );
        }
    } else {
        $cache_key = sprintf('analytics_revenue_%s_%s', $args{start_date} // 'all', $args{end_date} // 'now');
    }

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get($cache_key)) {
            return $cached;
        }
    }

    my $where_date = '';
    my @params;

    if ($args{start_date}) {
        $where_date .= ' AND date >= ?';
        push @params, $args{start_date};
    }
    if ($args{end_date}) {
        $where_date .= ' AND date <= ?';
        push @params, $args{end_date};
    }

    my ($total_revenue, $payments_count, $avg_payment) = $self->dbh->selectrow_array("
        SELECT
            IFNULL(SUM(money), 0) as total_revenue,
            COUNT(*) as payments_count,
            IFNULL(AVG(money), 0) as avg_payment
        FROM pays_history
        WHERE money > 0 $where_date
    ", undef, @params);

    my $result = {
        total_revenue => sprintf("%.2f", $total_revenue),
        payments_count => $payments_count,
        avg_payment => sprintf("%.2f", $avg_payment),
    };

    $self->cache->set($cache_key, $result, 3600);  # кеш на 1 час
    return $result;
}

# Выручка по месяцам
sub revenue_by_month {
    my $self = shift;
    my %args = (
        months => 12,  # последние N месяцев (0 = за всё время)
        no_cache => 0,
        @_,
    );

    my $cache_key = sprintf('analytics_revenue_by_month_%d', $args{months});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my $sql;
    my @params;

    # Текущий месяц (months = -1)
    if ($args{months} == -1) {
        $sql = "
            SELECT
                DATE_FORMAT(date, '%Y-%m') as month,
                SUM(money) as revenue,
                COUNT(*) as count
            FROM pays_history
            WHERE date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                AND money > 0
            GROUP BY DATE_FORMAT(date, '%Y-%m')
            ORDER BY month DESC
        ";
        @params = ();
    }
    elsif (defined $args{months} && $args{months} > 0) {
        # За последние N месяцев
        $sql = "
            SELECT
                DATE_FORMAT(date, '%Y-%m') as month,
                SUM(money) as revenue,
                COUNT(*) as count
            FROM pays_history
            WHERE date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
                AND money > 0
            GROUP BY DATE_FORMAT(date, '%Y-%m')
            ORDER BY month DESC
        ";
        @params = ($args{months});
    } else {
        # За всё время (months=0)
        $sql = "
            SELECT
                DATE_FORMAT(date, '%Y-%m') as month,
                SUM(money) as revenue,
                COUNT(*) as count
            FROM pays_history
            WHERE money > 0
            GROUP BY DATE_FORMAT(date, '%Y-%m')
            ORDER BY month DESC
        ";
        @params = ();
    }

    my $rows = $self->dbh->selectall_arrayref($sql, {Slice => {}}, @params);

    $self->cache->set_json($cache_key, $rows, 3600);
    return $rows;
}

# Выручка по дням (для периода 1 месяц или текущий месяц)
sub revenue_by_day {
    my $self = shift;
    my %args = (
        days => 30,
        current_month => 0,  # если 1, то берем данные с 1 числа текущего месяца
        no_cache => 0,
        @_,
    );

    my $cache_key = $args{current_month}
        ? 'analytics_revenue_by_day_current_month'
        : sprintf('analytics_revenue_by_day_%d', $args{days});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my ($sql, @params);
    if ($args{current_month}) {
        $sql = "
            SELECT
                DATE_FORMAT(date, '%Y-%m-%d') as day,
                ROUND(IFNULL(SUM(money), 0), 2) as revenue,
                COUNT(*) as count
            FROM pays_history
            WHERE date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                AND money > 0
            GROUP BY DATE_FORMAT(date, '%Y-%m-%d')
            ORDER BY day ASC
        ";
        @params = ();
    } else {
        $sql = "
            SELECT
                DATE_FORMAT(date, '%Y-%m-%d') as day,
                ROUND(IFNULL(SUM(money), 0), 2) as revenue,
                COUNT(*) as count
            FROM pays_history
            WHERE date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
                AND money > 0
            GROUP BY DATE_FORMAT(date, '%Y-%m-%d')
            ORDER BY day ASC
        ";
        @params = ($args{days});
    }

    my $rows = $self->dbh->selectall_arrayref($sql, {Slice => {}}, @params);

    # Обеспечиваем корректные типы данных для JSON
    for my $row (@$rows) {
        $row->{revenue} = sprintf("%.2f", $row->{revenue} || 0);
        $row->{count} = int($row->{count} || 0);
    }

    $self->cache->set_json($cache_key, $rows, 1800);
    return $rows;
}

# Выручка по неделям (для периода 3-6 месяцев)
sub revenue_by_week {
    my $self = shift;
    my %args = (
        months => 3,
        no_cache => 0,
        @_,
    );

    $args{months} = int($args{months} // 3);
    my $cache_key = sprintf('analytics_revenue_by_week_%d', $args{months});

    if ($args{no_cache}) {
        $self->cache->delete($cache_key);
    } else {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    # Вычисляем дату начала периода
    my ($start_date) = $self->dbh->selectrow_array(
        "SELECT DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL ? MONTH), '%Y-%m-%d')",
        undef, $args{months}
    );

    my $rows = $self->dbh->selectall_arrayref("
        SELECT
            CONCAT(YEAR(date), '-W', LPAD(WEEK(date, 1), 2, '0')) as week,
            MIN(DATE_FORMAT(date, '%Y-%m-%d')) as week_start,
            ROUND(IFNULL(SUM(money), 0), 2) as revenue,
            COUNT(*) as count
        FROM pays_history
        WHERE date >= ?
            AND money > 0
        GROUP BY YEAR(date), WEEK(date, 1)
        ORDER BY week ASC
    ", {Slice => {}}, $start_date) || [];

    # Обеспечиваем корректные типы данных для JSON
    for my $row (@$rows) {
        $row->{revenue} = sprintf("%.2f", $row->{revenue} || 0);
        $row->{count} = int($row->{count} || 0);
    }

    $self->cache->set_json($cache_key, $rows, 3600);
    return $rows;
}

# Прибыльность услуг (какие услуги приносят больше всего)
sub service_profitability {
    my $self = shift;
    my %args = (
        start_date => undef,
        end_date => undef,
        months => undef,  # альтернатива start_date - последние N месяцев (0 = за всё время)
        limit => 20,
        no_cache => 0,
        @_,
    );

    # Формируем ключ кеша на основе months или дат
    my $cache_key;
    if (defined $args{months}) {
        $cache_key = sprintf('analytics_service_profit_months_%d', $args{months});
        # Если указан months > 0, вычисляем start_date
        if ($args{months} > 0) {
            $args{start_date} = $self->dbh->selectrow_array(
                "SELECT DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL ? MONTH), '%Y-%m-%d')",
                undef, $args{months}
            );
        }
        # Если months = -1, это текущий месяц (с 1 числа по сегодня)
        elsif ($args{months} == -1) {
            $args{start_date} = $self->dbh->selectrow_array(
                "SELECT DATE_FORMAT(CURDATE(), '%Y-%m-01')"
            );
            $args{end_date} = $self->dbh->selectrow_array(
                "SELECT DATE_FORMAT(CURDATE(), '%Y-%m-%d')"
            );
        }
    } else {
        $cache_key = sprintf('analytics_service_profit_%s_%s',
            $args{start_date} // 'all', $args{end_date} // 'now');
    }

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my $where_date = '';
    my @params;

    if ($args{start_date}) {
        $where_date .= ' AND wd.withdraw_date >= ?';
        push @params, $args{start_date};
    }
    if ($args{end_date}) {
        $where_date .= ' AND wd.withdraw_date <= ?';
        push @params, $args{end_date};
    }
    push @params, $args{limit};

    my $rows = $self->dbh->selectall_arrayref("
        SELECT
            s.service_id,
            s.name as service_name,
            s.category,
            s.cost as base_cost,
            COUNT(DISTINCT wd.withdraw_id) as sales_count,
            COUNT(DISTINCT wd.user_id) as unique_buyers,
            SUM(wd.total) as total_revenue,
            SUM(wd.bonus) as bonuses_used,
            SUM(wd.total) - SUM(wd.bonus) as net_revenue,
            AVG(wd.total) as avg_sale,
            AVG(wd.discount) as avg_discount
        FROM withdraw_history wd
        INNER JOIN services s ON wd.service_id = s.service_id
        WHERE wd.withdraw_date IS NOT NULL $where_date
        GROUP BY s.service_id, s.name, s.category, s.cost
        ORDER BY total_revenue DESC
        LIMIT ?
    ", {Slice => {}}, @params);

    $self->cache->set_json($cache_key, $rows, 3600);
    return $rows;
}

# Ценность клиентов (топ клиентов по платежам)
sub top_clients {
    my $self = shift;
    my %args = (
        limit => 20,
        no_cache => 0,
        @_,
    );

    my $cache_key = sprintf('analytics_top_clients_%d', $args{limit});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my $rows = $self->dbh->selectall_arrayref("
        SELECT
            u.user_id,
            u.login,
            u.full_name,
            u.created as registration_date,
            u.balance,
            u.bonus,
            IFNULL(p.total_payments, 0) as total_payments,
            IFNULL(p.payments_count, 0) as payments_count,
            IFNULL(w.total_spent, 0) as total_spent,
            IFNULL(w.services_count, 0) as services_purchased,
            IFNULL(active_us.active_services, 0) as active_services
        FROM users u
        LEFT JOIN (
            SELECT user_id, SUM(money) as total_payments, COUNT(*) as payments_count
            FROM pays_history WHERE money > 0
            GROUP BY user_id
        ) p ON u.user_id = p.user_id
        LEFT JOIN (
            SELECT user_id, SUM(total) as total_spent, COUNT(DISTINCT service_id) as services_count
            FROM withdraw_history WHERE withdraw_date IS NOT NULL
            GROUP BY user_id
        ) w ON u.user_id = w.user_id
        LEFT JOIN (
            SELECT user_id, COUNT(*) as active_services
            FROM user_services WHERE status = 'ACTIVE'
            GROUP BY user_id
        ) active_us ON u.user_id = active_us.user_id
        WHERE u.block = 0
        ORDER BY total_payments DESC
        LIMIT ?
    ", {Slice => {}}, $args{limit});

    $self->cache->set_json($cache_key, $rows, 3600);
    return $rows;
}

# Топ партнёров (по приглашённым и заработанным бонусам)
sub top_partners {
    my $self = shift;
    my %args = (
        limit => 20,
        no_cache => 0,
        @_,
    );

    my $cache_key = sprintf('analytics_top_partners_%d', $args{limit});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my $rows = $self->dbh->selectall_arrayref("
        SELECT
            u.user_id,
            u.login,
            u.full_name,
            u.created as registration_date,
            u.bonus as current_bonus,
            IFNULL(refs.referrals_count, 0) as referrals_count,
            IFNULL(refs.active_referrals, 0) as active_referrals,
            IFNULL(refs.paying_referrals, 0) as paying_referrals,
            IFNULL(refs.referrals_revenue, 0) as referrals_revenue,
            IFNULL(b.total_earned, 0) as total_earned_bonuses,
            IFNULL(b.earnings_count, 0) as earnings_count
        FROM users u
        INNER JOIN (
            SELECT partner_id, COUNT(*) as referrals_count,
                SUM(CASE WHEN block = 0 THEN 1 ELSE 0 END) as active_referrals,
                0 as paying_referrals,
                0 as referrals_revenue
            FROM users
            WHERE partner_id IS NOT NULL AND partner_id > 0
            GROUP BY partner_id
        ) refs ON u.user_id = refs.partner_id
        LEFT JOIN (
            SELECT
                user_id,
                SUM(CASE WHEN bonus > 0 AND JSON_EXTRACT(comment, '\$.from_user_id') IS NOT NULL THEN bonus ELSE 0 END) as total_earned,
                COUNT(CASE WHEN bonus > 0 AND JSON_EXTRACT(comment, '\$.from_user_id') IS NOT NULL THEN 1 END) as earnings_count
            FROM bonus_history
            GROUP BY user_id
        ) b ON u.user_id = b.user_id
        WHERE u.block = 0
        ORDER BY total_earned_bonuses DESC, referrals_count DESC
        LIMIT ?
    ", {Slice => {}}, $args{limit});

    # Дополняем информацией о платящих рефералах
    for my $row (@$rows) {
        my ($paying, $revenue) = $self->dbh->selectrow_array("
            SELECT
                COUNT(DISTINCT p.user_id) as paying_referrals,
                IFNULL(SUM(p.money), 0) as referrals_revenue
            FROM pays_history p
            INNER JOIN users u ON p.user_id = u.user_id
            WHERE u.partner_id = ? AND p.money > 0
        ", undef, $row->{user_id});

        $row->{paying_referrals} = $paying || 0;
        $row->{referrals_revenue} = sprintf("%.2f", $revenue || 0);
        $row->{total_earned_bonuses} = sprintf("%.2f", $row->{total_earned_bonuses} || 0);
        $row->{current_bonus} = sprintf("%.2f", $row->{current_bonus} || 0);
    }

    $self->cache->set_json($cache_key, $rows, 3600);
    return $rows;
}

# === МЕТРИКИ ИСПОЛЬЗОВАНИЯ ===

# Популярные услуги по количеству активных подписок
sub popular_services {
    my $self = shift;
    my %args = (
        limit => 20,
        no_cache => 0,
        @_,
    );

    my $cache_key = sprintf('analytics_popular_services_%d', $args{limit});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my $rows = $self->dbh->selectall_arrayref("
        SELECT
            s.service_id,
            s.name as service_name,
            s.category,
            s.cost,
            COUNT(DISTINCT us.user_service_id) as active_subscriptions,
            COUNT(DISTINCT us.user_id) as unique_users,
            COUNT(DISTINCT CASE WHEN us.status = 'ACTIVE' THEN us.user_service_id END) as currently_active,
            COUNT(DISTINCT CASE WHEN us.status = 'BLOCK' THEN us.user_service_id END) as blocked
        FROM services s
        LEFT JOIN user_services us ON s.service_id = us.service_id AND us.status != 'REMOVED'
        WHERE s.deleted = 0
        GROUP BY s.service_id, s.name, s.category, s.cost
        ORDER BY active_subscriptions DESC
        LIMIT ?
    ", {Slice => {}}, $args{limit});

    $self->cache->set_json($cache_key, $rows, 3600);
    return $rows;
}

# Частота продлений (retention rate)
sub renewal_metrics {
    my $self = shift;
    my %args = (
        months => 6,  # 0 = за всё время
        no_cache => 0,
        @_,
    );

    my $cache_key = sprintf('analytics_renewal_%d', $args{months});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my ($total_services, $renewed_services, $avg_lifetime_days);

    # Текущий месяц (months = -1)
    if ($args{months} == -1) {
        ($total_services, $renewed_services) = $self->dbh->selectrow_array("
            SELECT
                COUNT(DISTINCT wd.user_service_id) as total,
                SUM(CASE WHEN renewals.renewal_count > 1 THEN 1 ELSE 0 END) as renewed
            FROM withdraw_history wd
            INNER JOIN (
                SELECT user_service_id, COUNT(*) as renewal_count
                FROM withdraw_history
                WHERE withdraw_date IS NOT NULL
                    AND withdraw_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                GROUP BY user_service_id
            ) renewals ON wd.user_service_id = renewals.user_service_id
            WHERE wd.withdraw_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
        ");

        ($avg_lifetime_days) = $self->dbh->selectrow_array("
            SELECT AVG(DATEDIFF(
                COALESCE(us.expire, CURDATE()),
                us.created
            )) as avg_lifetime
            FROM user_services us
            WHERE us.status != 'REMOVED'
                AND us.created >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
        ");
    }
    elsif (defined $args{months} && $args{months} > 0) {
        # За последние N месяцев
        ($total_services, $renewed_services) = $self->dbh->selectrow_array("
            SELECT
                COUNT(DISTINCT wd.user_service_id) as total,
                SUM(CASE WHEN renewals.renewal_count > 1 THEN 1 ELSE 0 END) as renewed
            FROM withdraw_history wd
            INNER JOIN (
                SELECT user_service_id, COUNT(*) as renewal_count
                FROM withdraw_history
                WHERE withdraw_date IS NOT NULL
                    AND withdraw_date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
                GROUP BY user_service_id
            ) renewals ON wd.user_service_id = renewals.user_service_id
            WHERE wd.withdraw_date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
        ", undef, $args{months}, $args{months});

        ($avg_lifetime_days) = $self->dbh->selectrow_array("
            SELECT AVG(DATEDIFF(
                COALESCE(us.expire, CURDATE()),
                us.created
            )) as avg_lifetime
            FROM user_services us
            WHERE us.status != 'REMOVED'
                AND us.created >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
        ", undef, $args{months});
    } else {
        # За всё время (months=0)
        ($total_services, $renewed_services) = $self->dbh->selectrow_array("
            SELECT
                COUNT(DISTINCT wd.user_service_id) as total,
                SUM(CASE WHEN renewals.renewal_count > 1 THEN 1 ELSE 0 END) as renewed
            FROM withdraw_history wd
            INNER JOIN (
                SELECT user_service_id, COUNT(*) as renewal_count
                FROM withdraw_history
                WHERE withdraw_date IS NOT NULL
                GROUP BY user_service_id
            ) renewals ON wd.user_service_id = renewals.user_service_id
        ");

        ($avg_lifetime_days) = $self->dbh->selectrow_array("
            SELECT AVG(DATEDIFF(
                COALESCE(us.expire, CURDATE()),
                us.created
            )) as avg_lifetime
            FROM user_services us
            WHERE us.status != 'REMOVED'
        ");
    }

    my $renewal_rate = $total_services > 0 ? ($renewed_services / $total_services * 100) : 0;

    my $result = {
        total_services => $total_services || 0,
        renewed_services => $renewed_services || 0,
        renewal_rate => sprintf("%.2f", $renewal_rate),
        avg_service_lifetime_days => sprintf("%.1f", $avg_lifetime_days || 0),
        period_months => $args{months},
    };

    $self->cache->set_json($cache_key, $result, 3600);
    return $result;
}

# Новые vs уходящие клиенты
sub churn_analysis {
    my $self = shift;
    my %args = (
        months => 3,  # 0 = за всё время
        no_cache => 0,
        @_,
    );

    my $cache_key = sprintf('analytics_churn_%d', $args{months});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my ($new_users, $paying_users, $inactive_users);

    # Заблокированные (ушедшие) пользователи - не зависит от периода
    my ($churned_users) = $self->dbh->selectrow_array("
        SELECT COUNT(*) FROM users
        WHERE block = 1
    ");

    # Текущий месяц (months = -1)
    if ($args{months} == -1) {
        ($new_users) = $self->dbh->selectrow_array("
            SELECT COUNT(*) FROM users
            WHERE created >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                AND block = 0
        ");

        ($paying_users) = $self->dbh->selectrow_array("
            SELECT COUNT(DISTINCT user_id) FROM pays_history
            WHERE date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                AND money > 0
        ");

        ($inactive_users) = $self->dbh->selectrow_array("
            SELECT COUNT(*) FROM users u
            WHERE u.block = 0
                AND NOT EXISTS (
                    SELECT 1 FROM pays_history p
                    WHERE p.user_id = u.user_id
                        AND p.date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                )
                AND EXISTS (
                    SELECT 1 FROM pays_history p2
                    WHERE p2.user_id = u.user_id
                )
        ");
    }
    elsif (defined $args{months} && $args{months} > 0) {
        # За последние N месяцев
        ($new_users) = $self->dbh->selectrow_array("
            SELECT COUNT(*) FROM users
            WHERE created >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
                AND block = 0
        ", undef, $args{months});

        ($paying_users) = $self->dbh->selectrow_array("
            SELECT COUNT(DISTINCT user_id) FROM pays_history
            WHERE date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
                AND money > 0
        ", undef, $args{months});

        ($inactive_users) = $self->dbh->selectrow_array("
            SELECT COUNT(*) FROM users u
            WHERE u.block = 0
                AND NOT EXISTS (
                    SELECT 1 FROM pays_history p
                    WHERE p.user_id = u.user_id
                        AND p.date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
                )
                AND EXISTS (
                    SELECT 1 FROM pays_history p2
                    WHERE p2.user_id = u.user_id
                )
        ", undef, $args{months});
    } else {
        # За всё время (months=0)
        ($new_users) = $self->dbh->selectrow_array("
            SELECT COUNT(*) FROM users
            WHERE block = 0
        ");

        ($paying_users) = $self->dbh->selectrow_array("
            SELECT COUNT(DISTINCT user_id) FROM pays_history
            WHERE money > 0
        ");

        # Неактивные = пользователи без платежей вообще (при months=0 это бессмысленно, но для согласованности)
        ($inactive_users) = $self->dbh->selectrow_array("
            SELECT COUNT(*) FROM users u
            WHERE u.block = 0
                AND NOT EXISTS (
                    SELECT 1 FROM pays_history p
                    WHERE p.user_id = u.user_id
                )
        ");
    }

    my $result = {
        new_users => $new_users || 0,
        paying_users => $paying_users || 0,
        churned_users => $churned_users || 0,
        inactive_users => $inactive_users || 0,
        period_months => $args{months},
    };

    $self->cache->set_json($cache_key, $result, 3600);
    return $result;
}

# === ОПЕРАЦИОННЫЕ ДАННЫЕ ===

# Эффективность платежей
sub payment_metrics {
    my $self = shift;
    my %args = (
        months => 3,  # 0 = за всё время
        no_cache => 0,
        @_,
    );

    my $cache_key = sprintf('analytics_payments_%d', $args{months});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my ($by_paysystem, $by_weekday);

    # Текущий месяц (months = -1)
    if ($args{months} == -1) {
        $by_paysystem = $self->dbh->selectall_arrayref("
            SELECT
                IFNULL(pay_system_id, 'manual') as pay_system,
                COUNT(*) as count,
                SUM(money) as total,
                AVG(money) as avg_amount
            FROM pays_history
            WHERE date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                AND money > 0
            GROUP BY pay_system_id
            ORDER BY total DESC
        ", {Slice => {}});

        $by_weekday = $self->dbh->selectall_arrayref("
            SELECT
                DAYOFWEEK(date) as weekday,
                COUNT(*) as count,
                SUM(money) as total
            FROM pays_history
            WHERE date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                AND money > 0
            GROUP BY DAYOFWEEK(date)
            ORDER BY weekday
        ", {Slice => {}});
    }
    elsif (defined $args{months} && $args{months} > 0) {
        # За последние N месяцев
        $by_paysystem = $self->dbh->selectall_arrayref("
            SELECT
                IFNULL(pay_system_id, 'manual') as pay_system,
                COUNT(*) as count,
                SUM(money) as total,
                AVG(money) as avg_amount
            FROM pays_history
            WHERE date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
                AND money > 0
            GROUP BY pay_system_id
            ORDER BY total DESC
        ", {Slice => {}}, $args{months});

        $by_weekday = $self->dbh->selectall_arrayref("
            SELECT
                DAYOFWEEK(date) as weekday,
                COUNT(*) as count,
                SUM(money) as total
            FROM pays_history
            WHERE date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
                AND money > 0
            GROUP BY DAYOFWEEK(date)
            ORDER BY weekday
        ", {Slice => {}}, $args{months});
    } else {
        # За всё время (months=0)
        $by_paysystem = $self->dbh->selectall_arrayref("
            SELECT
                IFNULL(pay_system_id, 'manual') as pay_system,
                COUNT(*) as count,
                SUM(money) as total,
                AVG(money) as avg_amount
            FROM pays_history
            WHERE money > 0
            GROUP BY pay_system_id
            ORDER BY total DESC
        ", {Slice => {}});

        $by_weekday = $self->dbh->selectall_arrayref("
            SELECT
                DAYOFWEEK(date) as weekday,
                COUNT(*) as count,
                SUM(money) as total
            FROM pays_history
            WHERE money > 0
            GROUP BY DAYOFWEEK(date)
            ORDER BY weekday
        ", {Slice => {}});
    }

    my $result = {
        by_paysystem => $by_paysystem,
        by_weekday => $by_weekday,
        period_months => $args{months},
    };

    $self->cache->set_json($cache_key, $result, 3600);
    return $result;
}

# Задолженность и эффективность списаний
sub billing_efficiency {
    my $self = shift;
    my %args = (
        no_cache => 0,
        @_,
    );

    my $cache_key = 'analytics_billing_efficiency';

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    # Неоплаченные списания (create_date есть, withdraw_date нет)
    my ($pending_withdraws, $pending_amount) = $self->dbh->selectrow_array("
        SELECT COUNT(*), IFNULL(SUM(total), 0)
        FROM withdraw_history
        WHERE withdraw_date IS NULL
    ");

    # Время между созданием списания и его оплатой
    my ($avg_pay_delay_hours) = $self->dbh->selectrow_array("
        SELECT AVG(TIMESTAMPDIFF(HOUR, create_date, withdraw_date))
        FROM withdraw_history
        WHERE withdraw_date IS NOT NULL
            AND create_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
    ");

    # Услуги, ожидающие оплаты
    my ($waiting_for_pay) = $self->dbh->selectrow_array("
        SELECT COUNT(*) FROM user_services
        WHERE status = 'WAIT_FOR_PAY'
    ");

    # Заблокированные за неоплату
    my ($blocked_services) = $self->dbh->selectrow_array("
        SELECT COUNT(*) FROM user_services
        WHERE status = 'BLOCK'
    ");

    my $result = {
        pending_withdraws => $pending_withdraws || 0,
        pending_amount => sprintf("%.2f", $pending_amount || 0),
        avg_payment_delay_hours => sprintf("%.1f", $avg_pay_delay_hours || 0),
        services_waiting_for_pay => $waiting_for_pay || 0,
        services_blocked => $blocked_services || 0,
    };

    $self->cache->set_json($cache_key, $result, 1800);  # кеш на 30 минут
    return $result;
}

# === ФИНАНСОВЫЕ ПОКАЗАТЕЛИ ===

# Lifetime Value (LTV) клиентов
sub ltv {
    my $self = shift;
    my %args = (
        no_cache => 0,
        @_,
    );

    my $cache_key = 'analytics_ltv';

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    # Средний LTV = среднее кол-во платежей * средний чек
    my ($avg_payments_per_user, $avg_payment_amount, $avg_ltv) = $self->dbh->selectrow_array("
        SELECT
            AVG(payments_count),
            AVG(avg_payment),
            AVG(total_paid)
        FROM (
            SELECT
                user_id,
                COUNT(*) as payments_count,
                AVG(money) as avg_payment,
                SUM(money) as total_paid
            FROM pays_history
            WHERE money > 0
            GROUP BY user_id
        ) user_stats
    ");

    # Время жизни клиента в месяцах
    my ($avg_customer_lifetime_months) = $self->dbh->selectrow_array("
        SELECT AVG(TIMESTAMPDIFF(MONTH, created, COALESCE(last_login, CURDATE())))
        FROM users
        WHERE block = 0
    ");

    my $result = {
        avg_payments_per_user => sprintf("%.2f", $avg_payments_per_user || 0),
        avg_payment_amount => sprintf("%.2f", $avg_payment_amount || 0),
        avg_ltv => sprintf("%.2f", $avg_ltv || 0),
        avg_customer_lifetime_months => sprintf("%.1f", $avg_customer_lifetime_months || 0),
    };

    $self->cache->set_json($cache_key, $result, 7200);  # кеш на 2 часа
    return $result;
}

# Дебиторская задолженность
sub receivables {
    my $self = shift;
    my %args = (
        no_cache => 0,
        @_,
    );

    my $cache_key = 'analytics_receivables';

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    # Пользователи с отрицательным балансом
    my $debtors = $self->dbh->selectall_arrayref("
        SELECT
            u.user_id,
            u.login,
            u.full_name,
            u.balance,
            u.created,
            u.last_login,
            (SELECT MAX(date) FROM pays_history WHERE user_id = u.user_id) as last_payment_date
        FROM users u
        WHERE u.balance < 0
            AND u.block = 0
        ORDER BY u.balance ASC
        LIMIT 50
    ", {Slice => {}});

    # Общая сумма задолженности
    my ($total_debt, $debtors_count) = $self->dbh->selectrow_array("
        SELECT SUM(ABS(balance)), COUNT(*)
        FROM users
        WHERE balance < 0 AND block = 0
    ");

    # Распределение задолженности по давности
    my $debt_aging = $self->dbh->selectall_arrayref("
        SELECT
            CASE
                WHEN DATEDIFF(CURDATE(), last_login) <= 7 THEN '0-7 days'
                WHEN DATEDIFF(CURDATE(), last_login) <= 30 THEN '8-30 days'
                WHEN DATEDIFF(CURDATE(), last_login) <= 90 THEN '31-90 days'
                ELSE '90+ days'
            END as age_bucket,
            COUNT(*) as users_count,
            SUM(ABS(balance)) as total_debt
        FROM users
        WHERE balance < 0 AND block = 0
        GROUP BY age_bucket
        ORDER BY MIN(DATEDIFF(CURDATE(), last_login))
    ", {Slice => {}});

    my $result = {
        total_debt => sprintf("%.2f", $total_debt || 0),
        debtors_count => $debtors_count || 0,
        top_debtors => $debtors,
        debt_aging => $debt_aging,
    };

    $self->cache->set_json($cache_key, $result, 1800);
    return $result;
}

# Объем начислений
sub charges_volume {
    my $self = shift;
    my %args = (
        months => 12,  # 0 = за всё время
        no_cache => 0,
        @_,
    );

    my $cache_key = sprintf('analytics_charges_%d', $args{months});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my ($charges_by_month, $revenue_vs_charges);

    # Текущий месяц (months = -1)
    if ($args{months} == -1) {
        $charges_by_month = $self->dbh->selectall_arrayref("
            SELECT
                DATE_FORMAT(withdraw_date, '%Y-%m') as month,
                SUM(total) as total_charged,
                SUM(bonus) as bonuses_used,
                GREATEST(SUM(total) - SUM(bonus), 0) as net_charged,
                COUNT(*) as transactions
            FROM withdraw_history
            WHERE withdraw_date IS NOT NULL
                AND withdraw_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
            GROUP BY DATE_FORMAT(withdraw_date, '%Y-%m')
            ORDER BY month DESC
        ", {Slice => {}});

        $revenue_vs_charges = $self->dbh->selectall_arrayref("
            SELECT
                m.month,
                IFNULL(p.revenue, 0) as revenue,
                IFNULL(w.total_charged, 0) as total_charged,
                IFNULL(w.bonuses_used, 0) as bonuses_used,
                IFNULL(w.money_charged, 0) as charges,
                IFNULL(p.revenue, 0) - IFNULL(w.money_charged, 0) as difference
            FROM (
                SELECT DATE_FORMAT(CURDATE(), '%Y-%m') as month
            ) m
            LEFT JOIN (
                SELECT DATE_FORMAT(date, '%Y-%m') as month, SUM(money) as revenue
                FROM pays_history
                WHERE money > 0 AND date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                GROUP BY DATE_FORMAT(date, '%Y-%m')
            ) p ON m.month = p.month
            LEFT JOIN (
                SELECT
                    DATE_FORMAT(withdraw_date, '%Y-%m') as month,
                    SUM(total) as total_charged,
                    SUM(bonus) as bonuses_used,
                    SUM(GREATEST(total - bonus, 0)) as money_charged
                FROM withdraw_history
                WHERE withdraw_date IS NOT NULL AND withdraw_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                GROUP BY DATE_FORMAT(withdraw_date, '%Y-%m')
            ) w ON m.month = w.month
        ", {Slice => {}});
    }
    elsif (defined $args{months} && $args{months} > 0) {
        # За последние N месяцев
        $charges_by_month = $self->dbh->selectall_arrayref("
            SELECT
                DATE_FORMAT(withdraw_date, '%Y-%m') as month,
                SUM(total) as total_charged,
                SUM(bonus) as bonuses_used,
                GREATEST(SUM(total) - SUM(bonus), 0) as net_charged,
                COUNT(*) as transactions
            FROM withdraw_history
            WHERE withdraw_date IS NOT NULL
                AND withdraw_date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
            GROUP BY DATE_FORMAT(withdraw_date, '%Y-%m')
            ORDER BY month DESC
        ", {Slice => {}}, $args{months});

        $revenue_vs_charges = $self->dbh->selectall_arrayref("
            SELECT
                m.month,
                IFNULL(p.revenue, 0) as revenue,
                IFNULL(w.total_charged, 0) as total_charged,
                IFNULL(w.bonuses_used, 0) as bonuses_used,
                IFNULL(w.money_charged, 0) as charges,
                IFNULL(p.revenue, 0) - IFNULL(w.money_charged, 0) as difference
            FROM (
                SELECT DISTINCT DATE_FORMAT(date, '%Y-%m') as month
                FROM pays_history
                WHERE date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
                UNION
                SELECT DISTINCT DATE_FORMAT(withdraw_date, '%Y-%m') as month
                FROM withdraw_history
                WHERE withdraw_date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
            ) m
            LEFT JOIN (
                SELECT DATE_FORMAT(date, '%Y-%m') as month, SUM(money) as revenue
                FROM pays_history WHERE money > 0
                GROUP BY DATE_FORMAT(date, '%Y-%m')
            ) p ON m.month = p.month
            LEFT JOIN (
                SELECT
                    DATE_FORMAT(withdraw_date, '%Y-%m') as month,
                    SUM(total) as total_charged,
                    SUM(bonus) as bonuses_used,
                    SUM(GREATEST(total - bonus, 0)) as money_charged
                FROM withdraw_history WHERE withdraw_date IS NOT NULL
                GROUP BY DATE_FORMAT(withdraw_date, '%Y-%m')
            ) w ON m.month = w.month
            ORDER BY m.month DESC
            LIMIT ?
        ", {Slice => {}}, $args{months}, $args{months}, $args{months});
    } else {
        # За всё время (months=0)
        $charges_by_month = $self->dbh->selectall_arrayref("
            SELECT
                DATE_FORMAT(withdraw_date, '%Y-%m') as month,
                SUM(total) as total_charged,
                SUM(bonus) as bonuses_used,
                GREATEST(SUM(total) - SUM(bonus), 0) as net_charged,
                COUNT(*) as transactions
            FROM withdraw_history
            WHERE withdraw_date IS NOT NULL
            GROUP BY DATE_FORMAT(withdraw_date, '%Y-%m')
            ORDER BY month DESC
        ", {Slice => {}});

        $revenue_vs_charges = $self->dbh->selectall_arrayref("
            SELECT
                m.month,
                IFNULL(p.revenue, 0) as revenue,
                IFNULL(w.total_charged, 0) as total_charged,
                IFNULL(w.bonuses_used, 0) as bonuses_used,
                IFNULL(w.money_charged, 0) as charges,
                IFNULL(p.revenue, 0) - IFNULL(w.money_charged, 0) as difference
            FROM (
                SELECT DISTINCT DATE_FORMAT(date, '%Y-%m') as month
                FROM pays_history
                UNION
                SELECT DISTINCT DATE_FORMAT(withdraw_date, '%Y-%m') as month
                FROM withdraw_history
                WHERE withdraw_date IS NOT NULL
            ) m
            LEFT JOIN (
                SELECT DATE_FORMAT(date, '%Y-%m') as month, SUM(money) as revenue
                FROM pays_history WHERE money > 0
                GROUP BY DATE_FORMAT(date, '%Y-%m')
            ) p ON m.month = p.month
            LEFT JOIN (
                SELECT
                    DATE_FORMAT(withdraw_date, '%Y-%m') as month,
                    SUM(total) as total_charged,
                    SUM(bonus) as bonuses_used,
                    SUM(GREATEST(total - bonus, 0)) as money_charged
                FROM withdraw_history WHERE withdraw_date IS NOT NULL
                GROUP BY DATE_FORMAT(withdraw_date, '%Y-%m')
            ) w ON m.month = w.month
            ORDER BY m.month DESC
        ", {Slice => {}});
    }

    my $result = {
        charges_by_month => $charges_by_month,
        revenue_vs_charges => $revenue_vs_charges,
        period_months => $args{months},
    };

    $self->cache->set_json($cache_key, $result, 3600);
    return $result;
}

# Начисления по дням (для периода 1 месяц или текущий месяц)
sub charges_by_day {
    my $self = shift;
    my %args = (
        days => 30,
        current_month => 0,  # если 1, то берем данные с 1 числа текущего месяца
        no_cache => 0,
        @_,
    );

    my $cache_key = $args{current_month}
        ? 'analytics_charges_by_day_current_month'
        : sprintf('analytics_charges_by_day_%d', $args{days});

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my ($sql, @params);
    if ($args{current_month}) {
        $sql = "
            SELECT
                DATE_FORMAT(withdraw_date, '%Y-%m-%d') as day,
                ROUND(IFNULL(SUM(total), 0), 2) as total_charged,
                ROUND(IFNULL(SUM(bonus), 0), 2) as bonuses_used,
                ROUND(GREATEST(IFNULL(SUM(total), 0) - IFNULL(SUM(bonus), 0), 0), 2) as net_charged,
                COUNT(*) as transactions
            FROM withdraw_history
            WHERE withdraw_date IS NOT NULL
                AND withdraw_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
            GROUP BY DATE_FORMAT(withdraw_date, '%Y-%m-%d')
            ORDER BY day ASC
        ";
        @params = ();
    } else {
        $sql = "
            SELECT
                DATE_FORMAT(withdraw_date, '%Y-%m-%d') as day,
                ROUND(IFNULL(SUM(total), 0), 2) as total_charged,
                ROUND(IFNULL(SUM(bonus), 0), 2) as bonuses_used,
                ROUND(GREATEST(IFNULL(SUM(total), 0) - IFNULL(SUM(bonus), 0), 0), 2) as net_charged,
                COUNT(*) as transactions
            FROM withdraw_history
            WHERE withdraw_date IS NOT NULL
                AND withdraw_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
            GROUP BY DATE_FORMAT(withdraw_date, '%Y-%m-%d')
            ORDER BY day ASC
        ";
        @params = ($args{days});
    }

    my $rows = $self->dbh->selectall_arrayref($sql, {Slice => {}}, @params);

    # Обеспечиваем корректные типы данных для JSON
    for my $row (@$rows) {
        $row->{total_charged} = sprintf("%.2f", $row->{total_charged} || 0);
        $row->{bonuses_used} = sprintf("%.2f", $row->{bonuses_used} || 0);
        $row->{net_charged} = sprintf("%.2f", $row->{net_charged} || 0);
        $row->{transactions} = int($row->{transactions} || 0);
    }

    $self->cache->set_json($cache_key, $rows, 1800);
    return $rows;
}

# Начисления по неделям (для периода 3-6 месяцев)
sub charges_by_week {
    my $self = shift;
    my %args = (
        months => 3,
        no_cache => 0,
        @_,
    );

    $args{months} = int($args{months} // 3);
    my $cache_key = sprintf('analytics_charges_by_week_%d', $args{months});

    if ($args{no_cache}) {
        $self->cache->delete($cache_key);
    } else {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    # Вычисляем дату начала периода
    my ($start_date) = $self->dbh->selectrow_array(
        "SELECT DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL ? MONTH), '%Y-%m-%d')",
        undef, $args{months}
    );

    my $rows = $self->dbh->selectall_arrayref("
        SELECT
            CONCAT(YEAR(withdraw_date), '-W', LPAD(WEEK(withdraw_date, 1), 2, '0')) as week,
            MIN(DATE_FORMAT(withdraw_date, '%Y-%m-%d')) as week_start,
            ROUND(IFNULL(SUM(total), 0), 2) as total_charged,
            ROUND(IFNULL(SUM(bonus), 0), 2) as bonuses_used,
            ROUND(GREATEST(IFNULL(SUM(total), 0) - IFNULL(SUM(bonus), 0), 0), 2) as net_charged,
            COUNT(*) as transactions
        FROM withdraw_history
        WHERE withdraw_date IS NOT NULL
            AND withdraw_date >= ?
        GROUP BY YEAR(withdraw_date), WEEK(withdraw_date, 1)
        ORDER BY week ASC
    ", {Slice => {}}, $start_date) || [];

    # Обеспечиваем корректные типы данных для JSON
    for my $row (@$rows) {
        $row->{total_charged} = sprintf("%.2f", $row->{total_charged} || 0);
        $row->{bonuses_used} = sprintf("%.2f", $row->{bonuses_used} || 0);
        $row->{net_charged} = sprintf("%.2f", $row->{net_charged} || 0);
        $row->{transactions} = int($row->{transactions} || 0);
    }

    $self->cache->set_json($cache_key, $rows, 3600);
    return $rows;
}

# === БОНУСНЫЕ МЕТРИКИ ===

# Бонусные метрики
sub bonus_metrics {
    my $self = shift;
    my %args = (
        months => undef,
        start_date => undef,
        end_date => undef,
        no_cache => 0,
        @_,
    );

    # Формируем ключ кеша
    my $cache_key;
    if (defined $args{months}) {
        $cache_key = sprintf('analytics_bonus_metrics_months_%d', $args{months});
        # Если указан months > 0, вычисляем start_date
        if ($args{months} > 0) {
            my ($start_date) = $self->dbh->selectrow_array(
                "SELECT DATE_SUB(CURDATE(), INTERVAL ? MONTH)",
                undef, $args{months}
            );
            $args{start_date} = $start_date;
        }
        # Если months = -1, это текущий месяц (с 1 числа по сегодня)
        elsif ($args{months} == -1) {
            $args{start_date} = $self->dbh->selectrow_array(
                "SELECT DATE_FORMAT(CURDATE(), '%Y-%m-01')"
            );
            $args{end_date} = $self->dbh->selectrow_array(
                "SELECT DATE_FORMAT(CURDATE(), '%Y-%m-%d')"
            );
        }
    } else {
        $cache_key = sprintf('analytics_bonus_metrics_%s_%s',
            $args{start_date} // 'all', $args{end_date} // 'now');
    }

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my $where_date = '';
    my @params;

    if ($args{start_date}) {
        $where_date .= ' AND date >= ?';
        push @params, $args{start_date};
    }
    if ($args{end_date}) {
        $where_date .= ' AND date <= ?';
        push @params, $args{end_date};
    }

    # 1. Общая сумма всех начисленных бонусов за период
    my ($total_bonuses) = $self->dbh->selectrow_array("
        SELECT COALESCE(SUM(bonus), 0)
        FROM bonus_history
        WHERE bonus > 0
            $where_date
    ", undef, @params);

    # 2. Бонусы от партнёров (где есть from_user_id в comment)
    my ($partner_bonuses) = $self->dbh->selectrow_array("
        SELECT COALESCE(SUM(bonus), 0)
        FROM bonus_history
        WHERE bonus > 0
            AND JSON_EXTRACT(comment, '\$.from_user_id') IS NOT NULL
            $where_date
    ", undef, @params);

    # 3. Процент партнерских бонусов от общей суммы бонусов
    my $partner_percent = $total_bonuses > 0
        ? ($partner_bonuses / $total_bonuses * 100)
        : 0;

    # 4. Использованные бонусы (из withdraw_history, поле bonus - списанные бонусы при оплате услуг)
    my $where_withdraw = $where_date;
    $where_withdraw =~ s/date/withdraw_date/g if $where_withdraw;

    my ($used_bonuses) = $self->dbh->selectrow_array("
        SELECT COALESCE(SUM(bonus), 0)
        FROM withdraw_history
        WHERE withdraw_date IS NOT NULL $where_withdraw
    ", undef, @params);

    # 5. Общий оборот (выручка за период)
    my ($total_revenue) = $self->dbh->selectrow_array("
        SELECT COALESCE(SUM(money), 0)
        FROM pays_history
        WHERE money > 0 $where_date
    ", undef, @params);

    # Расчет метрик
    my $bonus_load_percent = $total_revenue > 0
        ? ($used_bonuses / $total_revenue * 100)
        : 0;

    my $bonus_debt = $total_bonuses - $used_bonuses;

    my $debt_share_percent = $total_revenue > 0
        ? ($bonus_debt / $total_revenue * 100)
        : 0;

    my $result = {
        total_bonuses => sprintf("%.2f", $total_bonuses),
        partner_bonuses => sprintf("%.2f", $partner_bonuses),
        partner_percent => sprintf("%.1f", $partner_percent),
        used_bonuses => sprintf("%.2f", $used_bonuses),
        total_revenue => sprintf("%.2f", $total_revenue),
        bonus_load_percent => sprintf("%.2f", $bonus_load_percent),
        bonus_debt => sprintf("%.2f", $bonus_debt),
        debt_share_percent => sprintf("%.1f", $debt_share_percent),
    };

    $self->cache->set_json($cache_key, $result, 3600);
    return $result;
}

# === ОБЩИЙ ОТЧЕТ ===

# Сводный отчет по всем метрикам
sub api_report {
    my $self = shift;
    my %args = (
        months => -1,  # -1 = текущий месяц, 0 = за всё время
        no_cache => 0,
        @_,
    );

    my $subscription = get_service('Cloud::Subscription');
    unless ($subscription->check_subscription()) {
        report->status(403);
        report->add_error('Требуется активация подписки');
        return undef;
    }

    # Приводим months к числу для корректного сравнения
    $args{months} = int($args{months} // 6);

    my $cache_key = sprintf('analytics_full_report_%d', $args{months});

    if ($args{no_cache}) {
        # Удаляем кеш при явном запросе без кеша
        $self->cache->delete($cache_key);
    } else {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    # Подсчёт активных платящих за период
    my ($active_paying_users) = $self->dbh->selectrow_array("
        SELECT COUNT(DISTINCT us.user_id)
        FROM user_services AS us
        INNER JOIN withdraw_history AS wd ON us.withdraw_id = wd.withdraw_id
        WHERE
            us.status = 'ACTIVE' AND
            us.expire IS NOT NULL AND
            (wd.bonus > 0 OR wd.total > 0)
        ",);

    my $overview = $self->overview(no_cache => $args{no_cache});
    $overview->{active_paying_users} = $active_paying_users || 0;

    # Используем переданный months для всех методов
    # -1 = текущий месяц, 0 = за всё время, >0 = за N месяцев
    my $period = $args{months};

    # Определяем гранулярность данных для графиков
    # -1 или 1 месяц = по дням, остальные = по месяцам
    my ($revenue_timeline, $charges_timeline, $granularity);

    if ($args{months} == -1) {
        # Текущий месяц - данные с 1 числа
        $granularity = 'day';
        $revenue_timeline = $self->revenue_by_day(current_month => 1, no_cache => $args{no_cache}) || [];
        $charges_timeline = $self->charges_by_day(current_month => 1, no_cache => $args{no_cache}) || [];
    } elsif ($args{months} == 1) {
        # По дням за последние 35 дней
        $granularity = 'day';
        $revenue_timeline = $self->revenue_by_day(days => 35, no_cache => $args{no_cache}) || [];
        $charges_timeline = $self->charges_by_day(days => 35, no_cache => $args{no_cache}) || [];
    } else {
        # По месяцам (для всех остальных периодов)
        $granularity = 'month';
        $revenue_timeline = undef;  # Используем revenue_by_month
        $charges_timeline = undef;  # Используем charges_by_month из charges_volume
    }

    my $report = {
        generated_at => now(),
        period_months => $args{months},
        granularity => $granularity,

        # Общая статистика
        overview => $overview,

        # Финансы
        revenue => $self->revenue(months => $args{months}, no_cache => $args{no_cache}),
        revenue_by_month => $self->revenue_by_month(months => $period, no_cache => $args{no_cache}),
        revenue_timeline => $revenue_timeline,

        # Услуги
        service_profitability => $self->service_profitability(months => $args{months}, limit => 10, no_cache => $args{no_cache}),
        popular_services => $self->popular_services(limit => 10, no_cache => $args{no_cache}),

        # Клиенты
        top_clients => $self->top_clients(limit => 10, no_cache => $args{no_cache}),
        top_partners => $self->top_partners(limit => 10, no_cache => $args{no_cache}),
        churn => $self->churn_analysis(months => $period, no_cache => $args{no_cache}),

        # Операционка
        renewal => $self->renewal_metrics(months => $period, no_cache => $args{no_cache}),
        billing_efficiency => $self->billing_efficiency(no_cache => $args{no_cache}),
        payment_metrics => $self->payment_metrics(months => $period, no_cache => $args{no_cache}),

        # LTV и задолженность
        ltv => $self->ltv(no_cache => $args{no_cache}),
        receivables => $self->receivables(no_cache => $args{no_cache}),

        # Начисления
        charges => $self->charges_volume(months => $period, no_cache => $args{no_cache}),
        charges_timeline => $charges_timeline,

        # Бонусные метрики
        bonus_metrics => $self->bonus_metrics(months => $args{months}, no_cache => $args{no_cache}),
    };

    $self->cache->set_json($cache_key, $report, 3600);
    return $report;
}

# Краткая сводка (overview)
sub overview {
    my $self = shift;
    my %args = (
        no_cache => 0,
        @_,
    );

    my $cache_key = 'analytics_overview';

    unless ($args{no_cache}) {
        if (my $cached = $self->cache->get_json($cache_key)) {
            return $cached;
        }
    }

    my ($total_users, $active_users, $blocked_users) = $self->dbh->selectrow_array("
        SELECT
            COUNT(*),
            SUM(CASE WHEN block = 0 THEN 1 ELSE 0 END),
            SUM(CASE WHEN block = 1 THEN 1 ELSE 0 END)
        FROM users
    ");

    my ($total_services, $active_services) = $self->dbh->selectrow_array("
        SELECT
            COUNT(*),
            SUM(CASE WHEN status = 'ACTIVE' THEN 1 ELSE 0 END)
        FROM user_services WHERE status != 'REMOVED'
    ");

    my ($total_revenue) = $self->dbh->selectrow_array("
        SELECT SUM(money) FROM pays_history WHERE money > 0
    ");

    my ($total_balance, $total_bonus) = $self->dbh->selectrow_array("
        SELECT SUM(balance), SUM(bonus) FROM users WHERE block = 0
    ");

    # Используем метод active_count из User.pm
    my $active_paying_users = $self->user->active_count;

    my $result = {
        total_users => $total_users || 0,
        active_users => $active_users || 0,
        blocked_users => $blocked_users || 0,
        active_paying_users => $active_paying_users || 0,
        total_services => $total_services || 0,
        active_services => $active_services || 0,
        total_revenue => sprintf("%.2f", $total_revenue || 0),
        total_balance => sprintf("%.2f", $total_balance || 0),
        total_bonus => sprintf("%.2f", $total_bonus || 0),
    };

    $self->cache->set_json($cache_key, $result, 1800);
    return $result;
}

# Очистка кеша аналитики
sub clear_cache {
    my $self = shift;

    # Фиксированные ключи
    my @cache_keys = qw(
        analytics_overview
        analytics_ltv
        analytics_receivables
        analytics_billing_efficiency
    );

    # Ключи с периодами (месяцы)
    for my $months (-1, 0, 1, 3, 6, 12, 24, 120) {
        push @cache_keys, "analytics_full_report_$months";
        push @cache_keys, "analytics_revenue_months_$months";
        push @cache_keys, "analytics_service_profit_months_$months";
        push @cache_keys, "analytics_revenue_by_month_$months";
        push @cache_keys, "analytics_revenue_by_week_$months";
        push @cache_keys, "analytics_charges_by_week_$months";
        push @cache_keys, "analytics_charges_volume_$months";
        push @cache_keys, "analytics_charges_$months";
        push @cache_keys, "analytics_payment_metrics_$months";
        push @cache_keys, "analytics_payments_$months";
        push @cache_keys, "analytics_churn_$months";
        push @cache_keys, "analytics_renewal_$months";
        push @cache_keys, "analytics_bonus_metrics_months_$months";
    }

    # Ключи с днями
    for my $days (30, 35, 60) {
        push @cache_keys, "analytics_revenue_by_day_$days";
        push @cache_keys, "analytics_charges_by_day_$days";
    }

    # Ключи для текущего месяца
    push @cache_keys, 'analytics_revenue_by_day_current_month';
    push @cache_keys, 'analytics_charges_by_day_current_month';

    # Ключи с датами (общие/устаревшие)
    push @cache_keys, 'analytics_revenue_all_now';
    push @cache_keys, 'analytics_service_profit_all_now';
    push @cache_keys, 'analytics_top_clients_10';
    push @cache_keys, 'analytics_top_clients_20';
    push @cache_keys, 'analytics_popular_services_10';
    push @cache_keys, 'analytics_popular_services_20';
    push @cache_keys, 'analytics_top_partners_10';
    push @cache_keys, 'analytics_top_partners_20';

    for my $key (@cache_keys) {
        $self->cache->delete($key);
    }

    return { success => 1, message => 'Analytics cache cleared', keys_cleared => scalar(@cache_keys) };
}

1;
