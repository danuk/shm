package Core::Transport::Http;

use parent 'Core::Base';

use v5.32;
use utf8;
use Core::Base;
use Core::Const;
use Core::Utils qw(
    encode_json
    decode_json
    encode_utf8
);
use HTTP::Request::Common qw(
    GET
    POST
    PUT
    DELETE
    PATCH
    OPTIONS
);
use URI;
use URI::QueryParam;
use CGI;

sub send {
    my $self = shift;
    my $task = shift;
    my %server;

    if ( my $server = $task->server ) {
        %server = $server->get;
    } else {
        return undef, {
            error => 'Server not exists',
        };
    }

    my $template_id =   $task->event_settings->{template_id} ||
                        $task->settings->{template_id} ||
                        $server{settings}->{template_id};

    my $template = get_service('template', _id => $template_id );
    unless ( $template ) {
        return undef, {
            error => "template with id `$template_id` not found",
        }
    }

    my %settings = (
        %{ $server{settings} || {} },
        %{ $template->get_settings || {} },
        %{ $task->event_settings },
    );

    my $content = $template->parse(
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        task => $task,
    );

    my $method = lc( $settings{method} ) || 'post';
    unless ( $method =~ /^(get|post|put|delete|patch|options)$/ ) {
        return undef, {error => "unknown method `$method`"};
    }

    my $url = $template->parse(
        data => $server{host},
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        task => $task,
    );

    unless ( defined $url ) {
        return undef, {error => "not configure `URL`"};
    }

    my $verify_hostname = $settings{verify_hostname} // 1;
    my $timeout = $settings{timeout} || 10;

    my %request_args = (
        url => $url,
        method => $method,
        content_type => $settings{content_type},
        headers => $settings{headers},
        content => $content,
        verify_hostname => $verify_hostname,
        timeout => $timeout,
    );

    my $response = $self->http( %request_args );
    my %info = (
        request => \%request_args,
        response => $response->json_content || sprintf("*NOT_JSON* Length: %d", length $response->decoded_content ),
        status => {
            code => $response->code,
            line => $response->status_line,
        },
    );

    if ( $response->is_success ) {
        if ( my $name = $settings{storage_save_key} ) {
            get_service('storage')->save(
                $name,
                $response->json_content || $response->decoded_content,
            );
        }

        return SUCCESS, {
            %info,
            message => "successful",
        };
    } else {
        my $status = SUCCESS;
        # TODO: make array of success statuses
        if ( $response->code >= 500 ) {
            $status = FAIL;
        }

        return $status, {
            error => $response->status_line,
            %info,
        };
    }
}

sub HTTP::Response::json_content {
    my $self = shift;
    return decode_json( $self->decoded_content ) if $self->header('content-type') =~ m/application\/json/gi;
    return undef;
}

sub http {
    my $self = shift;
    my %args = (
        url => undef,
        method => 'post',
        content_type => '',
        headers => {},
        content => '',
        verify_hostname => 1,
        timeout => 10,
        binary => 0,
        @_,
    );

    $args{content_type} ||= 'application/json; charset=utf-8';

    my $method = uc $args{method};

    # Cache UA per timeout+verify_hostname combination
    state %ua_cache;
    my $cache_key = join('|', $args{timeout}, $args{verify_hostname} // 0);
    my $ua = $ua_cache{$cache_key} //= LWP::UserAgent->new(
        agent => 'SHM',
        timeout => $args{timeout},
        keep_alive => 4,
        ssl_opts => {
            verify_hostname => $args{verify_hostname},
        },
    );

    if ($method eq 'GET') {
        my $uri = URI->new($args{url});
        my %q = CGI->new($args{content})->Vars();
        $uri->query_param_append($_, $q{$_}) for keys %q;
        $args{url} = $uri->as_string;
    }

    my $content = $args{content};
    if ( ref $content ) {
        $content = encode_json( $content );
    }

    no strict 'refs';
    my $response = $ua->request( &{$method}(
        $args{url},
        Content_Type => $args{content_type},
        Content => encode_utf8( $content ),
        %{ $args{headers} || {} },
    ));

    $self->{response} = $response;

    logger->dump( $response->request );

    # Декодирование UTF-8 для текстового контента
    if (!$args{binary} && $response->is_success) {
        my $content = $response->decoded_content;
        if (!utf8::is_utf8($content)) {
            utf8::decode($content);
            # Заменяем контент в response объекте
            $response->{_content} = $content;
        }
    }

    return $response;
}

sub response { shift->{response} };

sub _http {
    my $self = shift;
    my $method = shift;
    my $url = shift;
    my %args = (
        binary => 0,
        get_smart_args( @_ ),
    );

    my $response = $self->http(
        method => $method,
        url => $url,
        %args,
    );

    if ($args{full_response}) {
        return {
            http_headers     => { $response->headers->flatten },
            http_code        => $response->code,
            http_status_line => $response->status_line,
            body             => $args{binary} ? $response->content : ($response->json_content || $response->decoded_content),
        };
    } else {
        return $args{binary} ? $response->content : ($response->json_content || $response->decoded_content);
    }
}

sub get { return shift->_http( 'get', @_ ) }
sub put { return shift->_http( 'put', @_ ) }
sub post { return shift->_http( 'post', @_ ) }
sub delete { return shift->_http( 'delete', @_ ) }
sub patch { return shift->_http( 'patch', @_ ) }
sub options { return shift->_http( 'options', @_ ) }

1;
