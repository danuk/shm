package Core::Billing::Simpler;

use v5.14;

use base qw(Exporter);

our @EXPORT_OK = qw(
    calc_end_date_by_months
    calc_total_by_date_range
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

1;
