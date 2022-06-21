package Core::Transport::Mail;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;

use MIME::Lite;
use MIME::Base64 qw(encode_base64);

sub send {
    my $self = shift;
    my $task = shift;

    my %server = $task->server->get;
    my %settings = (
        %{ $server{settings} || {} },
        %{ $task->event->{settings} || {} },
    );

    my $config = get_service("config")->data_by_name;

    $settings{from} //= $config->{mail}->{from};
    unless ( $settings{from} ) {
        return SUCCESS, {
            error => "From undefined",
        }
    }

    $settings{from_name} //= $config->{mail}->{from_name};

    $settings{subject} //= $config->{mail}->{subject};

    $settings{to} //= get_service('user')->emails || delete $settings{bcc};
    unless ( $settings{to} ) {
        return SUCCESS, {
            error => "User email undefined",
        }
    }

    my $message;
    if ( my $template_id = $settings{template_id} ) {

        my $template = get_service('template', _id => $template_id );
        unless ( $template ) {
            return SUCCESS, {
                error => "template not found",
            }
        }

        $message = $template->parse(
            $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
            task => $task,
        );

        %settings = (
            %settings,
            %{ $template->settings || {} },
        );
    } else {
        unless ( $message = $settings{message} ) {
            return SUCCESS, {
                error => "message undefined",
            }
        }
    }

    return $self->send_mail(
        message => $message,
        host => $server{host},
        %settings,
    );
}

sub send_mail {
    my $self = shift;
    my %args = (
        host => undef,
        from => undef,
        to => undef,
        subject => 'SHM',
        from_name => 'SHM',
        message => undef,
        @_,
    );

    my $msg = MIME::Lite->new(
        From    => sprintf("=?UTF-8?B?%s?= <%s>", MIME::Base64::encode_base64($args{from_name}), $args{from} ),
        To      => $args{to},
        Cc      => $args{cc} || "",
        BCc     => $args{bcc} || "",
        Subject => sprintf("=?UTF-8?B?%s?=", MIME::Base64::encode_base64($args{subject})),
        Type    => 'text/plain;charset=UTF-8',
        Data    =>  $args{message},
    );

    $msg->replace("X-Mailer", "SHM mailer");

    $msg->send(
        'smtp',
        $args{host},
        Debug => $args{debug} ? 1 : 0,
        $args{user} ? ( AuthUser => $args{user} ) : (),
        $args{password} ? ( AuthPass => $args{password} ) : (),
        $args{ssl} ? ( SSL => $args{ssl} ) : (),
    );

    return SUCCESS, {
        server => {
            host => $args{host},
        },
        mail => {
            %args,
        },
    };
}

1;
