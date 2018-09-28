package Core::Billing::Simpler;

use v5.14;
use Carp qw(confess);

use base qw(Exporter);

our @EXPORT = qw(
    calc_month_cost
    calc_end_date_by_months
    calc_total_by_date_range
);

use Core::Const;
use Core::Utils qw(string_to_utime utime_to_string start_of_month end_of_month parse_date days_in_months);
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

    my $days = $period =~/^\d+\.(\d+)$/ ? length($1) > 1 ? int($1) : int($1) * 10 : 0;
    my $months = int( $period );
    $days += $months * DAYS_IN_MONTH;

    my %stop = parse_date( $date );
    @stop{ qw/year month day hour min sec/ } = Add_Delta_DHMS( @stop{ qw/year month day hour min sec/ },$days,0,0,-1 );

    return sprintf("%d-%.2d-%.2d %.2d:%.2d:%.2d", @stop{ qw/year month day hour min sec/ } );
}

# Вычисляет стоимость услуги для заданного периода
sub calc_total_by_date_range {
    my %wd = (
        cost => undef,
        withdraw_date => undef,
        end_date => undef,
        @_,
    );
    my $debug = 0;

    for ( keys %wd ) {
        confess("`$_` required") unless defined $wd{ $_ };
    }

    my %start = parse_date( $wd{withdraw_date} );
    my %stop = parse_date( $wd{end_date} );

    # Add one second for correct counting days
    @stop{ qw/year month day hour min sec/ } = Add_Delta_DHMS( @stop{ qw/year month day hour min sec/ },0,0,0,1 );

    my %delta;
    @delta{ qw/day hour min sec/ } = Delta_DHMS( @start{ qw/year month day hour min sec/ }, @stop{ qw/year month day hour min sec/ } );

    my $cost_day = $wd{cost} / DAYS_IN_MONTH;
    my $cost_hour = $cost_day / 24;
    my $cost_min = $cost_hour / 60; 

    return sprintf("%.2f",
        $delta{day} * $cost_day +
        $delta{hour} * $cost_hour +
        $delta{min} * $cost_min
    );
}

1;
