package Core::S3;

use parent 'Core::Base';

use v5.32;
use utf8;
use Core::Base;
use POSIX qw(strftime);
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use MIME::Base64;
use URI;
use Core::Utils qw(
    encode_json
);

sub init {
    my $self = shift;
    my %args = @_;

    $self->{access_key} = $args{access_key};
    $self->{secret_key} = $args{secret_key};
    $self->{region} = $args{region} || 'ru-central1';
    $self->{service} = 's3';
    $self->{endpoint} = $args{endpoint} || "https://storage.yandexcloud.net";
    $self->{bucket} = $args{bucket};

    return $self;
}

sub setup { shift->init( get_smart_args @_ ) };

sub _signing_key {
    my $self = shift;
    my $date_stamp = shift;

    my $k_date = hmac_sha256($date_stamp, "AWS4" . $self->{secret_key});
    my $k_region = hmac_sha256($self->{region}, $k_date);
    my $k_service = hmac_sha256($self->{service}, $k_region);
    my $k_signing = hmac_sha256("aws4_request", $k_service);

    return $k_signing;
}

sub _canonical_request {
    my $self = shift;
    my %args = @_;

    my $method = $args{method} || 'GET';
    my $canonical_uri = $args{canonical_uri} || '/';
    my $canonical_querystring = $args{canonical_querystring} || '';
    my $canonical_headers = $args{canonical_headers} || '';
    my $signed_headers = $args{signed_headers} || '';
    my $payload_hash = $args{payload_hash} || sha256_hex('');

    return join("\n",
        $method,
        $canonical_uri,
        $canonical_querystring,
        $canonical_headers,
        $signed_headers,
        $payload_hash
    );
}

sub _string_to_sign {
    my $self = shift;
    my %args = @_;

    my $algorithm = 'AWS4-HMAC-SHA256';
    my $request_datetime = $args{request_datetime};
    my $credential_scope = $args{credential_scope};
    my $canonical_request_hash = $args{canonical_request_hash};

    return join("\n",
        $algorithm,
        $request_datetime,
        $credential_scope,
        $canonical_request_hash
    );
}

sub _auth_header {
    my $self = shift;
    my %args = @_;

    my $now = time();
    my $amz_date = strftime("%Y%m%dT%H%M%SZ", gmtime($now));
    my $date_stamp = strftime("%Y%m%d", gmtime($now));

    my $canonical_uri = $args{canonical_uri} || '/';
    my $canonical_querystring = $args{canonical_querystring} || '';
    my $payload_hash = $args{payload_hash} || sha256_hex('');
    my $host = $args{host} || URI->new($self->{endpoint})->host;

    # Canonical headers
    my @headers = (
        "host:$host",
        "x-amz-date:$amz_date"
    );

    my $canonical_headers = join("\n", sort @headers) . "\n";
    my @signed_headers_list = map { (split /:/, $_)[0] } @headers;
    my $signed_headers = join(';', sort @signed_headers_list);

    # Create canonical request
    my $canonical_request = $self->_canonical_request(
        method => $args{method} || 'GET',
        canonical_uri => $canonical_uri,
        canonical_querystring => $canonical_querystring,
        canonical_headers => $canonical_headers,
        signed_headers => $signed_headers,
        payload_hash => $payload_hash
    );

    my $canonical_request_hash = sha256_hex($canonical_request);

    # Create string to sign
    my $credential_scope = "$date_stamp/$self->{region}/$self->{service}/aws4_request";
    my $string_to_sign = $self->_string_to_sign(
        request_datetime => $amz_date,
        credential_scope => $credential_scope,
        canonical_request_hash => $canonical_request_hash
    );

    # Calculate signature
    my $signing_key = $self->_signing_key($date_stamp);
    my $signature = hmac_sha256_hex($string_to_sign, $signing_key);

    # Create authorization header
    my $authorization_header = "AWS4-HMAC-SHA256 " .
        "Credential=$self->{access_key}/$credential_scope, " .
        "SignedHeaders=$signed_headers, " .
        "Signature=$signature";

    return {
        'Authorization' => $authorization_header,
        'X-Amz-Date' => $amz_date,
        'Host' => $host
    };
}

sub get { shift->get_object( get_smart_args @_ ) };

sub get_object {
    my $self = shift;
    my %args = (
        bucket => $self->{bucket},
        key => undef,
        @_,
    );

    my $bucket = $args{bucket} || die "Bucket is required";
    my $key = $args{key} || die "Key is required";

    # Prepare URL
    my $uri = URI->new($self->{endpoint});
    $uri->path("/$bucket/$key");
    my $url = $uri->as_string;

    # Prepare canonical URI for signing
    my $canonical_uri = "/$bucket/$key";

    # Get authorization headers
    my $auth_headers = $self->_auth_header(
        method => 'GET',
        canonical_uri => $canonical_uri,
        host => $uri->host
    );

    # Create HTTP client
    my $http = get_service('Transport::Http');

    # Make request
    my $response = $http->http(
        method => 'GET',
        url => $url,
        headers => $auth_headers,
        content => '',
        timeout => 30
    );

    $self->{response} = $response;

    if ($response->is_success) {
        return $response->content;
    } else {
        return undef;
    }
}

sub response { shift->{response} };

1;