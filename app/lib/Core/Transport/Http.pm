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

    my %options;
    $options{agent} = $settings->{http}->{user_agent} // 'libwww-perl-shm';
    $options{ssl_opts}{verify_hostname} = $settings->{http}->{verify_hostname} // 1;
    $options{timeout} = $settings->{http}->{timeout} // 10;

    my $url = $settings->{http}->{url} // undef;
    unless ( defined $url ) {
        return undef, {
            error => "not configure `URL`",
        }
    }

    my $method = $settings->{http}->{method} // 'post';
    unless ( $method =~ m/^(get|post|put|delete)$/ ) {
        return undef, {
            error => "unknown method `$method`",
        }
    }

    my $content = $template->parse(
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        task => $task,
    );

    if ($method eq 'get') {
        $url .= sprintf("?%s", $content);
    }

    my $ua = LWP::UserAgent->new(%options);

    my %headers = %{$settings->{http}->{headers} || {}};
    foreach my $key (keys %headers) {
        $ua->default_headers->header($key => $headers{$key});
    }

    my $response = $ua->$method(
        $url,
        Content => $content
    );

    if ( $response->is_success ) {
        return SUCCESS, {
            message => "successful",
        }
    } else {
        return undef, {
            error => sprintf("%s / %s", $response->status_line, $response->decoded_content)
        }
    }
}

1;