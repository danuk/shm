package Core::Utils;

use v5.14;

use base qw(Exporter);

our @EXPORT_OK = qw(
    days_in_months
    parse_date
    start_of_month
    end_of_month
    http_limit
    http_content_range
    now
    parse_args
    string_to_utime
    utime_to_string
    decode_json
);

use Core::System::ServiceManager qw( get_service );
use Time::DaysInMonth;
use JSON;

our %in;

sub parse_date {
    my $date = shift;
    my %parse_date;
    @parse_date{ qw/year month day hour min sec tz/ } = map( int( $_ ), split(/\D+/, $date ) );
    return wantarray ? %parse_date : \%parse_date;
}

sub string_to_utime {
    my $string = shift or confess( "argument required" );

    my %d = parse_date( $string );

    $d{year} -= 1900;
    $d{month} -= 1;

    use Time::Local 'timelocal_nocheck';
    my $s_time = timelocal_nocheck( @d{ qw/sec min hour day month year/ } );
    return $s_time;
}

sub utime_to_string {
    my $time = shift || time;
    my $format = shift || "%Y-%m-%d %H:%M:%S";

    use POSIX qw(strftime);
    return strftime $format, localtime( $time );
}

*now = \&utime_to_string;

sub start_of_month {
    my $date = shift || now();

    substr ($date, 8) = '01 00:00:00';
    return $date;
}

sub end_of_month {
    my $date = shift || confess( 'date required' );


    my %data = parse_date( $date );
    return sprintf("%d-%.2d-%.2d 23:59:59", @data{ qw/year month/ }, days_in( @data{ qw/year month/} ) );
}

sub days_in_months {
    my $date = shift;

    if ( my %date = parse_date( $date ) ) {
        return days_in( @date{ qw/year month/ } );
    }
    else {
        confess("Incorrent date format: `$date`");
    }
}


sub period_to_string {
    my $period = shift;

    if ($period=~/^(\d+)\.(\d+)/)
    {
        my ($m, $d) = ($1, $2);

        my $ret;
        $ret .= int($m)." m " if $m > 0;
        $ret .= int($d)." d" if int($d) > 0;

        return $ret;
    }
    else {
        return $period . " m";
    }
}

sub parse_args {
    my $cgi = CGI->new;
    %in = $cgi->Vars;

    my %cmd_opts;
    for ( @ARGV ) {
        my ( $opt, $value ) = split(/=/);
        $opt =~s/\-+//;
        $cmd_opts{ $opt } = $value;
    }

    return %in, %cmd_opts;
}

sub http_limit {
    my $range = shift || $in{range};
    my %args = (
        rows => 25,
        offset => undef,
        @_,
    );

    if ($in{range}=~/^items=(\d+)-(\d+)$/) {
        ( $args{offset}, $args{rows} ) = ( $1, $2 );
    }

    $args{limit} = abs( $args{offset} - $args{rows} ) + 1;
    return %args;
}

sub http_content_range {
    my %args = (
        limit => undef,
        offset => undef,
        rows => undef,
        @_,
    );
    return ('Content-Range' => sprintf( "items %d-%d/%d", $args{offset}, $args{rows}, $args{count} ));
}

sub decode_json {
    my $data = shift || return undef;

    my $json;
    eval{ $json = JSON->new->utf8->decode( $data ) } or do {
        get_service('logger')->warning("Incorrect JSON data: " . $data);
    };

    return $json;
}

1;
