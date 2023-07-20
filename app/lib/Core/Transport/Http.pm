package Core::Transport::Http;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;

use LWP::UserAgent ();

sub send {
    my $self = shift;
    my $task = shift;

    my %settings = (
        %{ $task->event->{settings} || {} },
    );

    my $template = get_service('template', _id => $settings{template_id});
    unless ( $template ) {
        return undef, {
            error => "template with id `$settings{template_id}` not found",
        }
    }


    my $settings = $template->get_settings;

    # check method
    my $method = $settings->{http}->{method} // 'post';
    unless ( $method =~ m/^(get|post|put|delete)$/ ) {
        return undef, {error => "unknown method `$method`"};
    }

    # check url
    my $url = $settings->{http}->{url};
    unless ( defined $url ) {
        return undef, {error => "not configure `URL`"};
    }

    my %headers = %{$settings->{http}->{headers} || {}};

    my $content = $template->parse(
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        task => $task,
    );

    my $verify_hostname = $settings->{http}->{verify_hostname} // 1;

    my $timeout = $settings->{http}->{timeout} // 10;

    return $self->send_req({
        method => uc($method), # method uc
        url => $url,
        headers => %headers,
        configure => $content,
        verify_hostname => $verify_hostname,
        timeout => $timeout
    });
}

sub send_req {
    my $self = shift;
    my %args = (
        method => 'POST',
        url => undef,
        headers => {},
        content => undef,
        verify_hostname => 1,
        timeout => 10,
        @_,
    );

    $ua = LWP::UserAgent->(timeout => $args{timeout}, ssl_opts => { verify_hostname => $verify_hostname });

    my $req =  HTTP::Request->new($args{method} => $args{url});
    foreach my $key (keys %headers) {
        $req->header($key => $args{headers}{$key});
    }
    $req->content($args{content});

    my $response = $ua->request($req);

    if ( $response->is_success ) {
        return SUCCESS, {
            message => "successful",
        };
    } else {
        return undef, {
            error => sprintf("%s / %s", $response->status_line, $response->decoded_content)
        };
    }
}

1;
