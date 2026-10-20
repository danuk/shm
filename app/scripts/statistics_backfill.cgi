#!/usr/bin/perl

use v5.14;
use utf8;
use SHM qw(:all);
use Core::System::ServiceManager qw( get_service );

binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';
$| = 1;

my $dry_run  = grep { $_ eq '--dry-run' } @ARGV;
my $truncate = grep { $_ eq '--truncate' } @ARGV;    # очистить таблицу без вопроса

my $self  = SHM->new( user_id => 1 );
my $stats = get_service('statistics');
my $dbh   = $stats->dbh;

# Каждый шаг: kind, какие поля он заменяет (LIKE), и SQL, который отдаёт (date, field, count, sum, min, max).
# Имена полей совпадают с теми, что пишет Core::Base::stats.
my $sign = "IF(%s > 0, 'in', 'out')";
my @steps = (
    {
        title => 'Платежи',
        kind  => 'pay',
        like  => [ 'money', 'money:%' ],
        sql   => [
            q{SELECT DATE(date), 'money', COUNT(*), SUM(money), MIN(money), MAX(money)
              FROM pays_history WHERE date <= NOW() GROUP BY 1},
            sprintf( q{SELECT DATE(date), CONCAT('money:', %s), COUNT(*), SUM(ABS(money)), MIN(ABS(money)), MAX(ABS(money))
              FROM pays_history WHERE date <= NOW() AND money <> 0 GROUP BY 1, 2}, sprintf( $sign, 'money' ) ),
            sprintf( q{SELECT DATE(date), CONCAT('money:', %s, ':pay_system_id=', pay_system_id), COUNT(*), SUM(ABS(money)), MIN(ABS(money)), MAX(ABS(money))
              FROM pays_history WHERE date <= NOW() AND money <> 0 AND pay_system_id IS NOT NULL AND pay_system_id <> '' GROUP BY 1, 2}, sprintf( $sign, 'money' ) ),
        ],
    },
    {
        title => 'Списания',
        kind  => 'withdraw',
        like  => [ 'total', 'total:%', 'bonus' ],
        sql   => [
            q{SELECT DATE(withdraw_date), 'total', COUNT(*), SUM(total), MIN(total), MAX(total)
              FROM withdraw_history WHERE withdraw_date IS NOT NULL AND withdraw_date <= NOW() GROUP BY 1},
            q{SELECT DATE(withdraw_date), CONCAT('total:service_id=', service_id), COUNT(*), SUM(total), MIN(total), MAX(total)
              FROM withdraw_history WHERE withdraw_date IS NOT NULL AND withdraw_date <= NOW() GROUP BY 1, 2},
            q{SELECT DATE(withdraw_date), 'bonus', COUNT(*), SUM(bonus), MIN(bonus), MAX(bonus)
              FROM withdraw_history WHERE withdraw_date IS NOT NULL AND withdraw_date <= NOW() GROUP BY 1},
        ],
    },
    {
        title => 'Бонусы',
        kind  => 'bonus',
        like  => [ 'bonus', 'bonus:%' ],
        sql   => [
            q{SELECT DATE(date), 'bonus', COUNT(*), SUM(bonus), MIN(bonus), MAX(bonus)
              FROM bonus_history WHERE date <= NOW() GROUP BY 1},
            sprintf( q{SELECT DATE(date), CONCAT('bonus:', %s), COUNT(*), SUM(ABS(bonus)), MIN(ABS(bonus)), MAX(ABS(bonus))
              FROM bonus_history WHERE date <= NOW() AND bonus <> 0 GROUP BY 1, 2}, sprintf( $sign, 'bonus' ) ),
        ],
    },
    {
        title => 'Регистрации',
        kind  => 'user',
        like  => [ 'created', 'partner_id' ],
        sql   => [
            q{SELECT DATE(created), 'created', COUNT(*), COUNT(*), 1, 1
              FROM users WHERE created <= NOW() GROUP BY 1},
            q{SELECT DATE(created), 'partner_id', COUNT(*), COUNT(*), 1, 1
              FROM users WHERE created <= NOW() AND partner_id > 0 GROUP BY 1},
        ],
    },
    {
        title => 'Новые услуги',
        kind  => 'usobject',
        like  => [ 'created', 'created:%' ],
        sql   => [
            q{SELECT DATE(created), 'created', COUNT(*), COUNT(*), 1, 1
              FROM user_services WHERE created <= NOW() GROUP BY 1},
            q{SELECT DATE(created), CONCAT('created:service_id=', service_id), COUNT(*), COUNT(*), 1, 1
              FROM user_services WHERE created <= NOW() GROUP BY 1, 2},
        ],
    },
    {
        title => 'Промокоды',
        kind  => 'promo',
        like  => [ 'used' ],
        sql   => [
            q{SELECT DATE(used), 'used', COUNT(*), COUNT(*), 1, 1
              FROM promo_codes WHERE used IS NOT NULL AND used <= NOW() GROUP BY 1},
        ],
    },
);

say $dry_run ? 'Пересчёт статистики (dry-run — ничего не записывается)' : 'Пересчёт статистики по истории';
say '';

unless ($dry_run) {
    my $rows = $dbh->selectrow_array('SELECT COUNT(*) FROM statistics') || 0;
    if ( $rows && !$truncate ) {
        say "В таблице statistics сейчас строк: $rows.";
        say 'Очистить её целиком и записать заново?';
        say '  Внимание: задачи spool, переходы статусов услуг и продления из истории не восстанавливаются —';
        say '  после очистки они начнут копиться заново.';
        say '  Без очистки пересчитанные поля просто заменятся, остальные строки останутся.';
        print 'Очистить таблицу? [y/N]: ';
        my $answer = <STDIN> // '';    # без терминала (docker exec без -it) — ответ «нет»
        $truncate = $answer =~ /^\s*(y|yes|д|да)\s*$/i ? 1 : 0;
        say '';
    }
    if ( $truncate && $rows ) {
        $dbh->do('DELETE FROM statistics');
        $stats->commit;
        say "Таблица statistics очищена (удалено строк: $rows).";
        say '';
    }
}

my $total_rows = 0;
my $n = 0;
for my $step (@steps) {
    $n++;
    my $label = sprintf( '[%d/%d] %s', $n, scalar @steps, $step->{title} );

    my @rows;
    for my $sql ( @{ $step->{sql} } ) {
        my $res = eval { $dbh->selectall_arrayref($sql) };
        if ($@) {
            say "$label: ошибка запроса — пропускаю шаг";
            say "  $@";
            @rows = ();
            last;
        }
        push @rows, grep { defined $_->[0] } @$res;
    }
    unless (@rows) {
        say "$label: нет данных";
        next;
    }

    my @days = do { my %d; grep { !$d{$_}++ } map { $_->[0] } @rows };
    my $range = join ' — ', ( sort @days )[ 0, -1 ];

    if ($dry_run) {
        say sprintf( '%s: %d строк за %d дн. (%s)', $label, scalar @rows, scalar @days, $range );
        $total_rows += @rows;
        next;
    }

    # прошлые дни этих полей заменяем целиком
    my $like = join ' OR ', map { '`field` LIKE ?' } @{ $step->{like} };
    $dbh->do( "DELETE FROM statistics WHERE `kind` = ? AND `date` <= CURDATE() AND ($like)",
        undef, $step->{kind}, @{ $step->{like} } );

    my $i = 0;
    for my $r (@rows) {
        my ( $date, $field, $count, $sum, $min, $max ) = @$r;
        $stats->put( date => $date, kind => $step->{kind}, field => $field,
            count => $count, sum => $sum, min => $min, max => $max );
        progress( $label, ++$i, scalar @rows );
    }
    $stats->commit;
    say sprintf( '  %d строк за %d дн. (%s)', scalar @rows, scalar @days, $range );
    $total_rows += @rows;
}

say '';
say $dry_run ? "Будет записано строк: $total_rows" : "Готово, записано строк: $total_rows";

exit 0;

sub progress {
    my ( $label, $done, $all ) = @_;
    return unless $done == $all || $done % 50 == 0;
    my $width = 30;
    my $fill = int( $width * $done / $all );
    printf "\r%s: [%s%s] %3d%% (%d/%d)", $label, '#' x $fill, '.' x ( $width - $fill ), 100 * $done / $all, $done, $all;
    print "\n" if $done == $all;
}
