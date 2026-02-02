package Core::Utils;

use v5.14;
use utf8;
use MIME::Base64 ();
use CGI;
use CGI::Cookie;
use List::Util qw(
    first
    any
    all
    notall
    none
    uniq
);

use base qw(Exporter);

our @EXPORT = qw(
    switch_user
);

our @EXPORT_OK = qw(
    days_in_months
    parse_date
    parse_period
    sum_period
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
    is_ip_allowed
    trusted_ips

    first
    any
    all
    notall
    none
    uniq

    uniq_by_key
    format_time_diff
    exec_local_file
    qrencode
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
    N_Delta_YMDHMS
    Today_and_Now
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
    return undef if $data =~ /^\s*$/;
    return $data if ref $data;

    utf8::decode( $data );

    my $json;
    eval{ $json = JSON->new->latin1->relaxed->decode( $data ) } or do {
        get_service('logger')->error("Incorrect JSON field for decode: " . $data);
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

# Рекурсивная функция для преобразования специальных значений в JSON-совместимые
sub prepare_json_data {
    my $data = shift;

    if (ref $data eq 'SCALAR') {
        # \false -> false, \true -> true, \null -> null
        if ($$data eq 'false') {
            return JSON::false;
        } elsif ($$data eq 'true') {
            return JSON::true;
        } elsif ($$data eq 'null') {
            return undef;
        } else {
            return $data;
        }
    } elsif (ref $data eq 'HASH') {
        my %new_hash;
        for my $key (keys %$data) {
            $new_hash{$key} = prepare_json_data($data->{$key});
        }
        return \%new_hash;
    } elsif (ref $data eq 'ARRAY') {
        return [map { prepare_json_data($_) } @$data];
    } else {
        return $data;
    }
}

# convert to JSON as it is (with internal Perl encoding)
# for compatibility with other Cyrillic texts in the templates
sub encode_json_perl {
    my $data = shift || return undef;
    my %args = (
        pretty => 0,
        @_,
    );

    $data = prepare_json_data($data);

    my $json;
    eval{ $json = JSON->new->canonical->pretty( $args{pretty} )->encode( obj_to_json $data ) } or do {
        get_service('logger')->error("Incorrect JSON data for encode: " . $data);
    };

    return $json;
}

sub encode_json {
    my $data = shift || return undef;
    my %args = (
        pretty => 0,
        @_,
    );

    $data = prepare_json_data($data);

    my $json;
    eval{ $json = JSON->new->latin1->canonical->pretty( $args{pretty} )->encode( encode_utf8($data) ) } or do {
        get_service('logger')->error("Incorrect JSON data for encode: " . $data);
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
    my ($left, @right) = @_;
    $left = {} if ref $left ne 'HASH';

    for my $right (@right) {
        next if ref $right ne 'HASH';
        for my $key (keys %$right) {
            if (ref($right->{$key}) eq 'HASH' && ref($left->{$key}) eq 'HASH') {
                $left->{$key} = hash_merge($left->{$key}, $right->{$key});
            } else {
                $left->{$key} = $right->{$key};
            }
        }
    }
    return $left;
}

sub is_host {
    my $host = shift;

    return 1 if is_domain( $host );
    return 1 if is_ipv4( $host );
    return 1 if is_ipv6( $host );

    return 0;
}

sub ipv4_aton {
    my $ip = shift;
    my @o = split /\./, $ip;
    return ($o[0]<<24) + ($o[1]<<16) + ($o[2]<<8) + $o[3];
}

sub is_ip_allowed {
    my ($ip, $nets) = @_;
    return 0 unless $ip;

    if (is_ipv4($ip)) {
        my $ip_int = ipv4_aton($ip);
        for my $cidr (@$nets) {
            next unless $cidr =~ /^[0-9.]+/;
            my ($net, $masklen) = split '/', $cidr;
            $masklen //= 32;

            my $net_int = ipv4_aton($net);
            my $mask = $masklen == 0 ? 0 : (0xFFFFFFFF << (32 - $masklen)) & 0xFFFFFFFF;

            return 1 if ($ip_int & $mask) == ($net_int & $mask);
        }
    }
    elsif (is_ipv6($ip)) {
        require Socket;
        my $ip_bin = Socket::inet_pton(Socket::AF_INET6(), $ip);
        for my $cidr (@$nets) {
            next unless $cidr =~ /:/;
            my ($net, $masklen) = split '/', $cidr;
            $masklen //= 128;
            my $net_bin = Socket::inet_pton(Socket::AF_INET6(), $net);

            my $bits = $masklen;
            my $bytes = int($bits / 8);
            my $rem = $bits % 8;

            my $same = 1;
            for (my $i = 0; $i < $bytes; $i++) {
                if (substr($ip_bin, $i, 1) ne substr($net_bin, $i, 1)) {
                    $same = 0; last;
                }
            }
            if ($same && $rem > 0) {
                my $mask = 0xFF << (8 - $rem);
                my $b1 = unpack('C', substr($ip_bin, $bytes, 1));
                my $b2 = unpack('C', substr($net_bin, $bytes, 1));
                $same = (($b1 & $mask) == ($b2 & $mask));
            }
            return 1 if $same;
        }
    }
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

sub sum_period {
    my @periods = @_;

    my ($total_months, $total_days, $total_hours) = (0, 0, 0);

    for my $period (@periods) {
        next unless defined $period && $period ne '';

        my ($months, $days, $hours) = parse_period($period);
        $total_months += $months || 0;
        $total_days += $days || 0;
        $total_hours += $hours || 0;
    }

    # Нормализация: переводим часы в дни, дни в месяцы
    if ($total_hours >= 24) {
        $total_days += int($total_hours / 24);
        $total_hours = $total_hours % 24;
    }

    if ($total_days >= 30) {
        $total_months += int($total_days / 30);
        $total_days = $total_days % 30;
    }

    # Форматируем результат в формате M.DDHH
    my $result = sprintf("%d.%02d%02d", $total_months, $total_days, $total_hours);

    return wantarray ? ($total_months, $total_days, $total_hours) : $result;
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
        charset => 'utf-8',
        'Access-Control-Allow-Origin' => "$ENV{HTTP_ORIGIN}",
        'Access-Control-Allow-Credentials' => 'true',
        @_,
    );

    return undef if $is_header;

    # Не печатаем заголовки, если скрипт запущен не из под HTTP
    return undef unless $ENV{REQUEST_METHOD};

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

sub format_time_diff {
    my $target_date = shift or return '';
    my ($y1, $m1, $d1, $H1, $M1, $S1) = $target_date =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)$/;
    return '' unless defined $y1 && defined $m1 && defined $d1 && defined $H1 && defined $M1 && defined $S1;

    my ($y2, $m2, $d2, $H2, $M2, $S2) = Today_and_Now();

    my ($Dy,$Dm,$Dd,$Dh,$Dmin,$Ds);
    eval {
        ($Dy,$Dm,$Dd,$Dh,$Dmin,$Ds) = N_Delta_YMDHMS($y1,$m1,$d1,$H1,$M1,$S1, $y2,$m2,$d2,$H2,$M2,$S2);
    };
    return '' if $@;

    # Используем абсолютные значения для корректного отображения
    $Dy = abs($Dy);
    $Dm = abs($Dm);
    $Dd = abs($Dd);
    $Dh = abs($Dh);
    $Dmin = abs($Dmin);

    my @parts;

    push @parts, "$Dy " . ($Dy == 1 ? 'год' : $Dy >= 2 && $Dy <= 4 ? 'года' : 'лет') if $Dy;
    push @parts, "$Dm " . ($Dm == 1 ? 'месяц' : $Dm >= 2 && $Dm <= 4 ? 'месяца' : 'месяцев') if $Dm;
    push @parts, "$Dd " . (($Dd % 10 == 1 && $Dd % 100 != 11) ? 'день'
                     : ($Dd % 10 >= 2 && $Dd % 10 <= 4 && ($Dd % 100 < 10 || $Dd % 100 >= 20)) ? 'дня' : 'дней') if $Dd;
    push @parts, "$Dh " . (($Dh % 10 == 1 && $Dh % 100 != 11) ? 'час'
                     : ($Dh % 10 >= 2 && $Dh % 10 <= 4 && ($Dh % 100 < 10 || $Dh % 100 >= 20)) ? 'часа' : 'часов') if $Dh;
    push @parts, "$Dmin " . (($Dmin % 10 == 1 && $Dmin % 100 != 11) ? 'минута'
                     : ($Dmin % 10 >= 2 && $Dmin % 10 <= 4 && ($Dmin % 100 < 10 || $Dmin % 100 >= 20)) ? 'минуты' : 'минут') if $Dmin;

    return @parts ? join(', ', @parts[0..2]) : 'менее минуты';
}

sub uniq_by_key {
    my ($array_ref, $key) = @_;
    my %seen;
    return grep {
        !$seen{ $_->{$key} }++
    } @$array_ref;
}

sub exec_local_file {
    my %args = (
        stdin => undef,
        cmd => [],
        timeout => 3,
        @_,
    );

    return { error => "No command specified" } unless @{ $args{cmd} };

    use IPC::Open2;
    my ($reader, $writer);

    my $pid;
    eval {
        $pid = open2($reader, $writer, @{ $args{cmd} });
    };
    if ($@) {
        return { error => "Failed to execute command: $@" };
    }

    if (defined $args{stdin} && length $args{stdin}) {
        eval {
            print $writer $args{stdin};
        };
        if ($@) {
            kill 'TERM', $pid;
            waitpid($pid, 0);
            return { error => "Failed to write to stdin: $@" };
        }
    }
    close $writer;

    my $out = '';
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm($args{timeout});
        $out = do { local $/; <$reader> };
        alarm(0);
    };

    close $reader;

    if ($@ && $@ =~ /timeout/) {
        kill 'TERM', $pid;
        waitpid($pid, 0);
        return { error => "Command timed out after $args{timeout} seconds" };
    } elsif ($@) {
        kill 'TERM', $pid;
        waitpid($pid, 0);
        return { error => "Failed to read output: $@" };
    }

    waitpid($pid, 0);
    my $exit_code = $? >> 8;

    return {
        output => $out // '',
        exit_code => $exit_code,
        success => $exit_code == 0,
    };
}

sub qrencode {
    my $text = shift;
    my %args = (
        size => 3,              # размер модуля (1-50)
        margin => 4,            # отступ вокруг QR кода
        level => 'M',           # уровень коррекции ошибок (L/M/Q/H)
        format => 'PNG',        # формат вывода (PNG/SVG/EPS/PDF/etc)
        encoding => 'UTF-8',    # кодировка входного текста
        foreground => '000000', # цвет переднего плана (hex)
        background => 'FFFFFF', # цвет фона (hex)
        output_file => '-',     # файл для сохранения (опционально)
        @_,
    );

    return { error => "No text provided" } unless defined $text && length $text;

    unless ($args{level} =~ /^[LMQH]$/) {
        return { error => "Invalid error correction level. Use L, M, Q, or H" };
    }

    unless ($args{size} >= 1 && $args{size} <= 50) {
        return { error => "Invalid size. Must be between 1 and 50" };
    }

    unless ($args{margin} >= 0) {
        return { error => "Invalid margin. Must be >= 0" };
    }

    unless ($args{foreground} =~ /^[0-9A-Fa-f]{6}$/) {
        return { error => "Invalid foreground color. Use 6-digit hex format (e.g., '000000')" };
    }

    unless ($args{background} =~ /^[0-9A-Fa-f]{6}$/) {
        return { error => "Invalid background color. Use 6-digit hex format (e.g., 'FFFFFF')" };
    }

    my @cmd = (
        'qrencode',
        '-s', $args{size},
        '-m', $args{margin},
        '-l', $args{level},
        '-t', $args{format},
        '-o', $args{output_file},
        '--foreground=' . $args{foreground},
        '--background=' . $args{background}
    );

    push @cmd, $text;

    my $result = exec_local_file(
        cmd => \@cmd,
        timeout => 3,
    );

    if ($result->{error}) {
        return { error => "QR encode failed: " . $result->{error} };
    }

    unless ($result->{success}) {
        return {
            error => "QR encode failed with exit code " . $result->{exit_code},
            output => $result->{output}
        };
    }

    return {
        success => 1,
        $args{output_file} eq '-' ? ( data => $result->{output} ) : ( file => $args{output_file} ),
        format => $args{format},
        size => length($result->{output}),
        text_length => length($text)
    };
}

sub trusted_ips {
    my $additional_ips = shift;

    my @ip_ranges = qw(
        127.0.0.0/8
        172.16.0.0/12
        192.168.0.0/16
        10.0.0.0/8
    );

    if (my $trusted_ips = $ENV{TRUSTED_IPS}) {
        push @ip_ranges, map { s/^\s+|\s+$//gr } split /,/, $trusted_ips;
    }

    if ($additional_ips) {
        if (ref $additional_ips eq 'ARRAY') {
            push @ip_ranges, @$additional_ips;
        } elsif (!ref $additional_ips) {
            push @ip_ranges, map { s/^\s+|\s+$//gr } split /,/, $additional_ips;
        }
    }

    return @ip_ranges;
}

1;
