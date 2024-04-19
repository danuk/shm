package Core::Transport::Http;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;
use Core::Utils qw(
    encode_json
    decode_json
);
use LWP::UserAgent ();
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
    unless ( $method =~ /^(get|post|put|delete)$/ ) {
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

    my ( $response, $response_content ) = $self->http( %request_args );

    if ( $response->is_success ) {
        return SUCCESS, {
            message => "successful",
            request => \%request_args,
            response => $response_content,
        };
    } else {
        my $status = SUCCESS;
        if ( $response->status_line =~ /5\d{2}/ ) {
            $status = FAIL;
        }

        return $status, {
            error => $response->status_line,
            request => \%request_args,
            response => $response_content,
        };
    }
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
        @_,
    );

    $args{content_type} ||= 'application/json; charset=utf-8';

    my $method = lc( $args{method} );

    my $ua = LWP::UserAgent->new(
        agent => 'SHM',
        timeout => $args{timeout},
        ssl_opts => {
            verify_hostname => $args{verify_hostname},
        },
    );

    if ($method eq 'get') {
        my $uri = URI->new($args{url});
        my %q = CGI->new($args{content})->Vars();
        $uri->query_param_append($_, $q{$_}) for keys %q;
        $args{url} = $uri->as_string;
    }

    my $content = $args{content};
    if ( ref $content ) {
        $content = encode_json( $content );
    }

    my $response = $ua->$method(
        $args{url},
        Content_Type => $args{content_type},
        Content => $content,
        %{ $args{headers} || {} },
    );

    my $response_content = $response->decoded_content;
    if ( $response->header('content-type') =~ m/application\/json/gi ) {
        $response_content = decode_json( $response_content );
    }

    logger->dump( $response->request );

    return $response, $response_content;
}

1;
