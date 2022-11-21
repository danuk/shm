package Core::Utils;

use v5.14;
use utf8;
use Encode qw/_utf8_on/;

use base qw(Exporter);

our @EXPORT = qw(
    switch_user
);

our @EXPORT_OK = qw(
    days_in_months
    parse_date
    start_of_month
    end_of_month
    http_limit
    http_content_range
    now
    parse_args
    parse_headers
    string_to_utime
    utime_to_string
    decode_json
    to_json
    force_numbers
    file_by_string
    read_file
    passgen
    shm_test_api
    is_email
    html_escape
    hash_merge
);

use Core::System::ServiceManager qw( get_service delete_service );
use Time::DaysInMonth;
use JSON qw//;
use Scalar::Util qw(looks_like_number);
use File::Temp;
use Data::Validate::Email qw(is_email);

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

sub get_uri_args {
    my %in;

    if ( $ENV{QUERY_STRING} ) {
        delete local $ENV{REQUEST_METHOD};
        my $q = CGI->new( $ENV{QUERY_STRING} );
        %in = $q->Vars;
    }
    return %in;
}

sub parse_headers {
    my $cgi = CGI->new;
    my %headers = map { $_ => $cgi->http($_) } $cgi->http();

    return %headers;
}

sub parse_args {
    my $cgi = CGI->new;
    %in = $cgi->Vars;

    if ( $ENV{CONTENT_TYPE} =~/application\/json/i ) {
        my $method = $ENV{REQUEST_METHOD};
        _utf8_on( $in{ "${method}DATA" } );
        my $json = decode_json( $in{ "${method}DATA" } );
        if ( $json ) {
            %in = %{ $json };
        }
        delete $in{ "${method}DATA" };
        return %in, get_uri_args();
    }

    _utf8_on( $in{ $_ } ) for keys %in;

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
    eval{ $json = JSON->new->decode( $data ) } or do {
        get_service('logger')->warning("Incorrect JSON data: " . $data);
    };

    return $json;
}

sub force_numbers {
    if (ref $_[0] eq ""){
        if ( looks_like_number($_[0]) ){
            $_[0] += 0;
        }
    } elsif ( ref $_[0] eq 'ARRAY' ){
        force_numbers($_) for @{$_[0]};
    } elsif ( ref $_[0] eq 'HASH' ) {
        force_numbers($_) for values %{$_[0]};
    }
    return $_[0];
}

sub file_by_string {
    my $string = shift;

    my $fh = File::Temp->new( UNLINK => 0, SUFFIX => '.dat' );
    print $fh $string;
    $fh->seek( 0, SEEK_END );
    return $fh->filename;
}

sub read_file {
    my $file = shift;

    open my $fh, $file or return undef;
    local $/;
    my $data = <$fh>;
    close($fh);

    return $data;
}

sub switch_user {
    my $user_id = shift;

    get_service('logger')->debug('Switch user to: ', $user_id );

    my $config = get_service('config');
    $config->local('authenticated_user_id', $user_id ) unless $config->local('authenticated_user_id');
    $config->local('user_id', $user_id );

    delete_service('user');
}

sub passgen {
    my $len = shift || 10;
    my @chars =('e','r','t','p','a','d','f','h','k','z','x','c','b','n','m', 'E','R','T','P','A','D','F','H','K','Z','X','C','B','N','M', 1 .. 9);
    my $pass = join("", @chars[ map { rand @chars } (1 .. $len) ]);
    return $pass;
}

sub shm_test_api {
    my %args = (
        url => undef,
        method => 'get',
        login => undef,
        password => undef,
        data => undef,
        @_,
    );

    use LWP::UserAgent ();
    my $ua = LWP::UserAgent->new(timeout => 3);

    $ua->default_header('Content-Type' => 'application/json');
    $ua->default_header('login' => $args{login}) if $args{login};
    $ua->default_header('password' => $args{password}) if $args{password};

    my $method = lc $args{method};
    my $response = $ua->$method(
        sprintf( "http://shm.local/shm/%s", $args{url} ),
        $args{data} ? $args{data} : (),
    );

    return (
        success => $response->is_success,
        content => $response->decoded_content,
        json => decode_json( $response->decoded_content ),
        status_line => $response->status_line,
    );
}

sub html_escape {
    my $data = shift;

    my %map = (
        "&" => "&amp;",
        "<" => "&lt;",
        ">" => "&gt;",
        '"' => '&quot;',
        "'" => '&#39;',
        "/" => '&#x2F;',
    );

    my $chars = join '', keys %map;
    $data =~s/([$chars])/$map{$1}/g;

    return $data;
}

sub hash_merge {
    shift unless ref $_[0];
    my ($left, @right) = @_;

    return $left unless @right;

    return hash_merge($left, hash_merge(@right)) if @right > 1;

    my ($right) = @right;

    my %merge = %$left;

    for my $key (keys %$right) {

        my ($hr, $hl) = map { ref $_->{$key} eq 'HASH' } $right, $left;

        if ($hr and $hl) {
            $merge{$key} = hash_merge($left->{$key}, $right->{$key});
        }
        else {
            $merge{$key} = $right->{$key};
        }
    }
    return \%merge;
}

1;
