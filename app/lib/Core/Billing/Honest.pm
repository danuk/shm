package Core::Billing::Honest;

# Известные проблемы:
# - Нельзя подсчитать итоговую стоимость неоплаченной услуги (услуги в корзине) для периода, заданного в днях (не полный месяц), так как
#   мы не знаем, когда услуга будет оплачена и соотвественно не знаем стоимость дня.
# - Не используйте этот модуль для заказа услуг на дробные периоды

use v5.14;
use Carp qw(confess);

use base qw(Exporter);

our @EXPORT_OK = qw(
    calc_month_cost
    calc_end_date_by_months
    calc_total_by_date_range
    calc_period_by_total
);

use Core::Const;
use Core::Utils qw(
    string_to_utime
    utime_to_string
    start_of_month
    end_of_month
    parse_date
    parse_period
    days_in_months
    now
);
use Time::Local 'timelocal_nocheck';
use Time::DaysInMonth;
use Data::Dumper;

use Date::Calc qw(
    Add_Delta_DHMS
    Delta_YMD
);

# Вычисляет стоимость в пределах одного месяца
# На вход принимает стоимость и дату смещения
sub calc_month_cost {
    my $args = {
        cost => undef,
        to_date => undef,   # считать с начала месяца, до указанной даты [****....]
        from_date => undef, # считать с указанной даты, до конца месяца  [....****]
        @_,
    };

    unless ( $args->{from_date} || $args->{to_date} ) {
        confess( 'from_date or to_date required' );
    }

    my ( $total, $start_date, $stop_date );

    $start_date = $args->{from_date} || start_of_month( $args->{to_date} ) ;
    $stop_date = $args->{to_date} || end_of_month( $args->{from_date} );

    my $sec_absolute = abs( string_to_utime( $stop_date ) - string_to_utime( $start_date ) );

    if ( $sec_absolute ) {
        my $sec_in_month = days_in_months( $start_date ) * 86400 - 1;
        $total = $args->{cost} / ( $sec_in_month / $sec_absolute );
    }

    return {    start => $start_date,
                stop => $stop_date,
                total => sprintf("%.2f", $total )
    };
}

# Вычисляет конечную дату путем прибавления периода к заданной дате
sub calc_end_date_by_months {
    my $date = shift;
    my $period = shift;

    my ( $months, $days, $hours ) = parse_period( $period );

    my ( $start_year, $start_mon, $start_day, $start_hour, $start_min, $start_sec ) = split(/\D+/, $date );

    my $sec_in_start = days_in_months( $date ) * 86400 - 1;
    my $unix_stop = timelocal_nocheck( 0, 0, $hours, 1 + $days , $start_mon + $months - 1, $start_year + int( ( $start_mon + $months - 1 ) / 12 ) );
    my $sec_in_stop = days_in_months( utime_to_string( $unix_stop ) ) * 86400 - 1;

    my $ttt = $sec_in_start - ( ( $start_day - 1 ) * 86400 + $start_hour * 3600 + $start_min * 60 + $start_sec );
    $ttt = 1 if $ttt == 0;

    my $diff = $sec_in_start / $ttt;
    $diff = 1 if $diff == 0; # devision by zero

    my $end_date = $unix_stop + int( $sec_in_stop - ($sec_in_stop / $diff) );

    return utime_to_string( $end_date - 1 );  # 23:59:59
}

# Вычисляет стоимость услуги для заданного периода
sub calc_total_by_date_range {
    my %wd = (
        cost => undef,
        period => 1,
        withdraw_date => now,
        end_date => undef,
        @_,
    );

    my %start = parse_date( $wd{withdraw_date} );
    my %stop = parse_date( $wd{end_date} );

    my $total = 0;

    if ( $wd{cost} ) {
        my $m_diff = ( $stop{month} + $stop{year} * 12 ) - ( $start{month} + $start{year} * 12 );

        if ( $wd{period} && $wd{period} != 1 ) {
            my ( $months, $days, $hours ) = parse_period( $wd{period} );
            # TODO: add support days and hours
            $wd{cost} = $wd{cost} / $months if $months;
        }

        # calc first month
        if ( $wd{end_date} le end_of_month( $wd{withdraw_date} ) ) {
            # Услуга начинается и заканчивается в одном месяце
            my $data = calc_month_cost( cost => $wd{cost}, from_date => $wd{withdraw_date}, to_date => $wd{end_date} );
            $total = $data->{total};
        }
        else {
            # Услуга начинается в одном месяце, а заканчивается в другом
            my $data = calc_month_cost( cost => $wd{cost}, from_date => $wd{withdraw_date} );
            $total = $data->{total};
        }

        # calc middle
        if ($m_diff > 1) {
            my $middle_total = $wd{cost} * ( $m_diff - 1 );
            $total += $middle_total;
        }

        # calc last month
        if ($m_diff > 0) {
            my $data = calc_month_cost( cost => $wd{cost}, to_date => $wd{end_date} );
            $total += $data->{total};
        }
    }

    return {
        total => sprintf("%.2f", $total ),
        months => calc_months_between_dates(\%start, \%stop),
    };
}

sub calc_months_between_dates {
    my %start = %{ $_[0] };
    my %stop = %{ $_[1] };

    @stop{ qw/year month day hour min sec/ } = Add_Delta_DHMS( @stop{ qw/year month day hour min sec/ }, 0,0,0,1 ); # add one second

    # TODO: calc delta hours
    my %delta;
    @delta{ qw/year month day/ } = Delta_YMD(
        @start{ qw/year month day/ },
        @stop{ qw/year month day/ }
    );

    if ( $delta{day} < 0 ) {
        my $days = days_in( @start{ qw/year month/ } );
        $delta{month}--;
        $delta{day} = $days - $start{day} + $stop{day};
    }

    return sprintf('%d.%02d',
        $delta{year} * 12 + $delta{month},
        $delta{day}),
}

# Вычисляет период, который можно получить за указанную сумму
# Возвращает период в формате M.DD (с календарными днями)
# где M - месяцы, DD - дни (2 цифры, календарные)
sub calc_period_by_total {
    my %args = (
        total => undef,           # Сумма, которую готовы потратить
        cost => undef,            # Стоимость услуги за период
        period => 1,              # Период услуги (в месяцах или формате M.DD)
        reference_date => now(),  # Опорная дата для календарных расчетов
        @_,
    );

    return '0.00' unless $args{total} && $args{cost} && $args{cost} > 0;

    my $total = $args{total};
    my $cost = $args{cost};
    my $period = $args{period} || 1;
    my $ref_date = $args{reference_date};

    # Корректируем стоимость если период не равен 1 месяцу
    my $monthly_cost = $cost;
    if ( $period && $period != 1 ) {
        my ( $months, $days, $hours ) = parse_period( $period );
        # Упрощенная логика: если есть месяцы, делим на количество месяцев
        $monthly_cost = $cost / $months if $months && $months > 0;
    }

    # Начинаем с опорной даты
    my $current_date = $ref_date;
    my $remaining_total = $total;
    my $total_months = 0;
    my $total_days = 0;

    # Стратегия: сначала тратим полные месяцы, потом дни
    while ($remaining_total >= $monthly_cost) {
        $remaining_total -= $monthly_cost;
        $total_months++;

        # Переходим к следующему месяцу для корректного расчета дней
        my %date_parts = parse_date($current_date);
        $date_parts{day} = 1;  # Переходим к началу месяца
        if ($date_parts{month} == 12) {
            $date_parts{year}++;
            $date_parts{month} = 1;
        } else {
            $date_parts{month}++;
        }
        $current_date = sprintf("%d-%.2d-%.2d %.2d:%.2d:%.2d",
            @date_parts{ qw/year month day hour min sec/ });
    }

    # Теперь считаем дни из остатка
    if (defined $remaining_total && $remaining_total > 0) {
        my $days_in_current_month = days_in_months($current_date);
        my $cost_per_day = $monthly_cost / $days_in_current_month;

        $total_days = int($remaining_total / $cost_per_day);

        # Если остается еще денег, добавляем один день (округление вверх)
        if (($remaining_total % $cost_per_day) > 0 && $total_days < $days_in_current_month) {
            $total_days++;
        }
    }

    # Возвращаем период в формате M.DD
    return sprintf('%d.%02d', $total_months, $total_days);
}

1;
