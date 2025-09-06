package Core::Utils;

use v5.14;
use utf8;
use MIME::Base64 ();
use CGI;
use CGI::Cookie;

use base qw(Exporter);

our @EXPORT = qw(
    switch_user
);

our @EXPORT_OK = qw(
    days_in_months
    parse_date
    parse_period
    add_date_time
    start_of_month
    start_of_day
    end_of_month
    http_limit
    http_content_range
    now
    parse_args
    parse_headers
    get_cookies
    string_to_utime
    utime_to_string
    decode_json
    encode_json
    encode_utf8
    encode_json_perl
    encode_base64
    encode_base64url
    decode_base64
    decode_base64url
    file_by_string
    read_file
    write_file
    passgen
    shm_test_api
    is_email
    is_host
    html_escape
    hash_merge
    blessed
    get_random_value
    to_query_string
    dots_str_to_sql
    uuid_gen
    print_header
    print_json
    get_user_ip
);

use Core::System::ServiceManager qw( get_service delete_service );
use Time::DaysInMonth;
use JSON qw//;
use Scalar::Util qw(blessed);
use File::Temp;
use Data::Validate::Email qw(is_email);
use Data::Validate::Domain qw(is_domain);
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Clone 'clone';
use Date::Calc qw(
    Add_Delta_YMDHMS
);

our %in;
our $is_header = 0;
my $cgi = CGI->new;

sub parse_date {
    my $date = shift || now();
    my %parse_date;
    @parse_date{ qw/year month day hour min sec/ } = map( $_, split(/\D+/, $date ) );
    %parse_date = map { $_ => int $parse_date{ $_ } } keys %parse_date ; # convert undef to 0
    return wantarray ? %parse_date : \%parse_date;
}

sub string_to_utime {
    my $string = shift || now();

    my %d = parse_date( $string );

    $d{year} -= 1900;
    $d{month} -= 1;

    use Time::Local 'timelocal_nocheck';
    my $s_time = timelocal_nocheck( @d{ qw/sec min hour day month year/ } );
    return $s_time;
}

sub now { utime_to_string( time ) };

sub utime_to_string {
    my $time = shift || time;
    my $format = shift || "%Y-%m-%d %H:%M:%S";

    use POSIX qw(strftime);
    return strftime $format, localtime( $time );
}

sub add_date_time {
    my $date = shift || now();
    my %args = (
        year => 0,
        month => 0,
        day => 0,
        hour => 0,
        min => 0,
        sec => 0,
        @_,
    );

    my %date = parse_date( $date );

    my @ret = Add_Delta_YMDHMS(
        @date{ qw/year month day hour min sec/ },
        @args{ qw/year month day hour min sec/}
    );

    return sprintf("%d-%.2d-%.2d %.2d:%.2d:%.2d", @ret[0..5] );
}

sub start_of_month {
    my $date = shift || now();

    substr ($date, 8) = '01 00:00:00';
    return $date;
}

sub start_of_day {
    my $date = shift || now();

    substr ($date, 11) = '00:00:00';
    return $date;
}

sub end_of_month {
    my $date = shift || now();

    my %data = parse_date( $date );
    return sprintf("%d-%.2d-%.2d 23:59:59", @data{ qw/year month/ }, days_in( @data{ qw/year month/} ) );
}

sub days_in_months {
    my $date = shift || now();

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
    return wantarray ? %in : \%in;
}

sub parse_headers {
    my $cgi = CGI->new;
    my %headers = map { $_ => $cgi->http($_) } $cgi->http();

    # add lower case headers without prefix
    for my $key (keys %headers) {
        my $new_key = $key;
        $new_key =~s/^HTTP_//;
        $headers{ lc $new_key } = $headers{ $key };
    }

    return wantarray ? %headers : \%headers;
}

sub parse_args {
    my %args = (
        auto_parse_json => 1,
        @_,
    );

    my $cgi = CGI->new;
    %in = $cgi->Vars;

    if ( $args{auto_parse_json} && $ENV{CONTENT_TYPE} =~/application\/json/i ) {
        my $method = $ENV{REQUEST_METHOD};
        my $json = decode_json( $in{ "${method}DATA" } );
        if ( $json ) {
            if ( ref $json eq 'HASH' ) {
                %in = %{ $json };
            } else {
                $in{DATA} = $json;
            }
        }
        delete $in{ "${method}DATA" };
        return %in, get_uri_args();
    } elsif ( $ENV{REQUEST_METHOD} eq 'GET' ) {
        utf8::decode( $in{ $_ } ) for keys %in;
    }

    my %cmd_opts;
    for ( @ARGV ) {
        my ( $opt, $value ) = split(/=/);
        $opt =~s/\-+//;
        $cmd_opts{ $opt } = $value;
    }

    return wantarray ? ( %in, %cmd_opts ) : { %in, %cmd_opts };
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

    utf8::decode( $data );

    my $json;
    eval{ $json = JSON->new->latin1->relaxed->decode( $data ) } or do {
        get_service('logger')->warning("Incorrect JSON field for decode: " . $data);
    };

    return $json;
}

sub obj_to_json {
    my $data = shift;

    if (blessed $data) {
        if ( $data->can('res') ) {
            $data = $data->res();
        }
    }

    if (ref $data eq 'HASH') {
        for (keys %$data) {
            if (blessed $data->{$_}) {
                $data->{$_} = obj_to_json($data->{$_});
            }
        }
    }
    return $data;
}

# convert to JSON as it is (with internal Perl encoding)
# for compatibility with other Cyrillic texts in the templates
sub encode_json_perl {
    my $data = shift || return undef;
    my %args = (
        pretty => 0,
        @_,
    );

    my $json;
    eval{ $json = JSON->new->canonical->pretty( $args{pretty} )->encode( obj_to_json $data ) } or do {
        get_service('logger')->warning("Incorrect JSON data for encode: " . $data);
    };

    return $json;
}

sub encode_json {
    my $data = shift || return undef;
    my %args = (
        pretty => 0,
        @_,
    );

    my $json;
    eval{ $json = JSON->new->latin1->canonical->pretty( $args{pretty} )->encode( encode_utf8($data) ) } or do {
        get_service('logger')->warning("Incorrect JSON data for encode: " . $data);
    };

    return $json;
}

# converting an internal Perl strings to octets (bytes)
sub encode_utf8 {
    my $data = clone( shift );
    _encode_utf8( $data );
    return $data;
}

sub _encode_utf8 {
    if ( ref $_[0] eq 'HASH' ) {
        _encode_utf8( $_ ) for values %{$_[0]};
    } elsif ( ref $_[0] eq 'ARRAY' ){
        _encode_utf8( $_ ) for @{$_[0]};
    } else {
        utf8::encode($_[0]) if utf8::is_utf8($_[0]);
    }
}

sub file_by_string {
    my $string = shift;

    my $fh = File::Temp->new( UNLINK => 0, SUFFIX => '.dat' );
    print $fh $string;
    #$fh->seek( 0, SEEK_END );
    close($fh);
    return $fh->filename;
}

sub read_file {
    my $file = shift;

    open my $fh, $file or return { error => $! };
    local $/;
    my $data = <$fh>;
    close($fh);

    return $data;
}

sub write_file {
    my $file = shift;
    my $data = shift;

    open my $fh, '>', $file or return { error => $! };
    print $fh ref $data ? encode_json( $data ) : encode_utf8( $data );
    close $fh;

    return 1;
}

sub switch_user {
    my $user_id = shift;

    get_service('logger')->debug('Switch user to:', $user_id );

    my $config = get_service('config');
    $config->local('authenticated_user_id', $user_id ) unless $config->local('authenticated_user_id');
    $config->local('user_id', $user_id );
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
        sprintf( "http://api/shm/%s", $args{url} ),
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

sub encode_base64 {
    return MIME::Base64::encode_base64( shift );
}

sub decode_base64 {
    return MIME::Base64::decode_base64( shift );
}

sub encode_base64url {
    return MIME::Base64::encode_base64url( shift );
}

sub decode_base64url {
    return MIME::Base64::decode_base64url( shift );
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

sub is_host {
    my $host = shift;

    return 1 if is_domain( $host );
    return 1 if is_ipv4( $host );
    return 1 if is_ipv6( $host );

    return 0;
}

sub get_cookies {
    my $name = shift;

    my %cookies = fetch CGI::Cookie;

    if ( $name ) {
        return undef unless $cookies{ $name };
        return $cookies{ $name }->value;
    } else {
        return wantarray ? %cookies : \%cookies;
    }
}

sub parse_period {
    my $period = shift;

    my ( $months, $parts ) = split(/\./, $period );

    my $days =  $parts =~/^(\d{1,2})/ ?      ( length($1) == 1 ? int($1) * 10 : int($1) ) : 0;
    my $hours = $parts =~/^\d{2}(\d{1,2})/ ? ( length($1) == 1 ? int($1) * 10 : int($1) ) : 0;

    return wantarray ? (
        $months,
        $days,
        $hours,
    ) : {
        months => $months,
        days => $days,
        hours => $hours,
    };
}

sub get_random_value {
    my $value = shift;

    if ( ref $value eq 'ARRAY' ) {
        return $value->[ int rand scalar @$value ];
    } else {
        return $value;
    }
}

sub to_query_string {
    my $data = shift;
    return undef unless $data ne 'HASH';

    use URI::Escape;
    my @ret;
    for ( keys %$data ) {
        push @ret, sprintf("%s=%s", $_, uri_escape_utf8( $data->{ $_ } ));
    }
    return join('&', @ret );
}

sub dots_str_to_sql {
    my $str = shift;

    my @arr = split(/\./, $str);
    return undef unless @arr;

    my $field = shift @arr;
    return undef unless @arr;

    return {
        field => $field,
        name => join('_', $field, @arr),
        query => sprintf('%s->>"$.%s"', $field, join('.', @arr)),
    }
}

sub uuid_gen {
    my $uuid = `cat /proc/sys/kernel/random/uuid`;
    chomp $uuid;
    return $uuid;
}

sub print_header {
    my %args = (
        status => 200,
        type => 'application/json',
        charset => 'utf8',
        'Access-Control-Allow-Origin' => "$ENV{HTTP_ORIGIN}",
        'Access-Control-Allow-Credentials' => 'true',
        @_,
    );

    return undef if $is_header;

    print $cgi->header( map +( "-$_" => $args{$_} ), keys %args );
    $is_header = 1;
}

sub print_json {
    my $ref = shift || [];
    my %args = (
        @_,
    );

    die 'WTF? blessed object' if blessed $ref;

    # if $ref contained 'status' set to header
    print_header( ref $ref eq 'HASH' ? %{ $ref } : () ) unless $is_header;

    say encode_json( $ref );
}

sub get_user_ip {
    return $ENV{HTTP_X_REAL_IP} || $ENV{REMOTE_ADDR};
}

# метод для вычисления разницы дат
# метод вывода даты в формате: "2 дня, 4 часа, 5 минут"

1;
