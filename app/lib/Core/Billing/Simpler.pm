package Core::Billing::Simpler;

use v5.14;

use base qw(Exporter);

our @EXPORT_OK = qw(
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

use constant DAYS_IN_MONTH => 30;

use Date::Calc qw(
    Delta_DHMS
    Add_Delta_DHMS
);

# Вычисляет конечную дату путем прибавления периода к заданной дате
sub calc_end_date_by_months {
    my $date = shift;
    my $period = shift;

    my ( $months, $days, $hours ) = parse_period( $period );

    $days += $months * DAYS_IN_MONTH;

    my %stop = parse_date( $date );
    @stop{ qw/year month day hour min sec/ } = Add_Delta_DHMS( @stop{ qw/year month day hour min sec/ },$days,$hours,0,-1 );

    return sprintf("%d-%.2d-%.2d %.2d:%.2d:%.2d", @stop{ qw/year month day hour min sec/ } );
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
    my $debug = 0;

    my %start = parse_date( $wd{withdraw_date} );
    my %stop = parse_date( $wd{end_date} );

    my $total = 0;

    if ( $wd{cost} ) {
        # Add one second for correct counting days
        @stop{ qw/year month day hour min sec/ } = Add_Delta_DHMS( @stop{ qw/year month day hour min sec/ },0,0,0,1 );

        my %delta;
        @delta{ qw/day hour min sec/ } = Delta_DHMS( @start{ qw/year month day hour min sec/ }, @stop{ qw/year month day hour min sec/ } );

        my $months_cost;
        if ( my $pc = $wd{period} ) {
            if ( int( $pc ) == $pc ) {
                $months_cost = $wd{cost} / $wd{period};
            } else {
                my $months_hours = DAYS_IN_MONTH * 24;
                my ( $months, $days, $hours ) = parse_period( $pc );
                my $period_hours = $months * DAYS_IN_MONTH * 24 + $days * 24 + $hours;
                $months_cost = $months_hours / $period_hours * $wd{cost};
            }
        }

        my $cost_day = $months_cost / DAYS_IN_MONTH;
        my $cost_hour = $cost_day / 24;
        my $cost_min = $cost_hour / 60;

        $total = $delta{day} * $cost_day + $delta{hour} * $cost_hour + $delta{min} * $cost_min;
    }

    return {
        total => sprintf("%.2f", $total ),
        months => calc_months_between_dates(\%start, \%stop),
    };
}

sub calc_months_between_dates {
    my %start = %{ $_[0] };
    my %stop = %{ $_[1] };

    my %delta;
    @delta{ qw/day hour min sec/ } = Delta_DHMS( @start{ qw/year month day hour min sec/ }, @stop{ qw/year month day hour min sec/ } );

    my $months = int( $delta{day} / DAYS_IN_MONTH );
    my $days =  $delta{day} % DAYS_IN_MONTH;
    my $hours = $delta{hour};

    return sprintf('%d.%02d%02d', $months, $days, $hours);
}

# Вычисляет период, который можно получить за указанную сумму
# Возвращает период в формате parse_period: M.DDHH
# где M - месяцы, DD - дни (2 цифры), HH - часы (2 цифры)
sub calc_period_by_total {
    my %args = (
        total => undef,     # Сумма, которую готовы потратить
        cost => undef,      # Стоимость услуги за период
        period => 1,        # Период услуги (в месяцах или формате M.DDHH)
        @_,
    );

    return '0.0000' unless $args{total} && $args{cost} && $args{cost} > 0;

    my $total = $args{total};
    my $cost = $args{cost};
    my $period = $args{period} || 1;

    # Вычисляем стоимость за месяц
    my $months_cost;
    if ( int( $period ) == $period ) {
        # Период задан целым числом месяцев
        $months_cost = $cost / $period;
    } else {
        # Период задан в формате M.DDHH
        my $months_hours = DAYS_IN_MONTH * 24;
        my ( $months, $days, $hours ) = parse_period( $period );
        my $period_hours = $months * DAYS_IN_MONTH * 24 + $days * 24 + $hours;
        $months_cost = $months_hours / $period_hours * $cost;
    }

    # Вычисляем стоимость за день, час и минуту
    my $cost_day = $months_cost / DAYS_IN_MONTH;
    my $cost_hour = $cost_day / 24;
    my $cost_min = $cost_hour / 60;

    # Определяем количество времени, которое можно купить за total
    my $total_minutes = $total / $cost_min;

    # Преобразуем минуты в дни и часы
    my $total_hours = int($total_minutes / 60);
    my $remaining_minutes = $total_minutes % 60;

    # Преобразуем часы в дни
    my $total_days = int($total_hours / 24);
    my $remaining_hours = $total_hours % 24;

    # Преобразуем дни в месяцы
    my $months = int($total_days / DAYS_IN_MONTH);
    my $days = $total_days % DAYS_IN_MONTH;

    # Если есть остаток минут, округляем часы вверх
    if (defined $remaining_minutes && $remaining_minutes > 0) {
        $remaining_hours++;
        if ($remaining_hours >= 24) {
            $days++;
            $remaining_hours = 0;
            if ($days >= DAYS_IN_MONTH) {
                $months++;
                $days = 0;
            }
        }
    }

    # Возвращаем период в формате M.DDHH
    return sprintf('%d.%02d%02d', $months, $days, $remaining_hours);
}

1;
