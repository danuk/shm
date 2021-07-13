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
    my $settings = $task->event->{settings};

    my $config = get_service("config")->data_by_name;

    my $from = $settings->{mail}->{from} || $config->{mail}->{from};
    unless ( $from ) {
        return FAIL, {
            error => "From undefined",
        }
    }

    $settings->{subject} //= "Mail from: $config->{company}->{name}";

    my ( $to ) = get_service('user')->emails;
    unless ( $to ) {
        return SUCCESS, {
            error => "User email undefined",
        }
    }

    my $template_id = $settings->{template_id};
    unless ( $template_id ) {
        return FAIL, {
            error => "template_id undefined",
        }
    }

    my $template = get_service('template', _id => $template_id );
    unless ( $template ) {
        return FAIL, {
            error => "template not found",
        }
    }

    my $message = $template->parse(
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
    );

    return $self->send_mail(
        host => $server{host},
        from => $from,
        to => $to,
        subject => '',
        message => $message,
        template_id => $template_id,
        %{ $settings || {} },
    );
}

sub send_mail {
    my $self = shift;
    my %args = (
        host => undef,
        from => undef,
        to => undef,
        subject => undef,
        message => undef,
        @_,
    );

    my $subject = MIME::Base64::encode_base64( $args{subject} );

    my $msg = MIME::Lite->new(
        From    => $args{from},
        To      => $args{to},
        Cc      => "",
        BCc     => "",
        Subject => "=?UTF-8?B?$subject?=",
        Type    => 'text/plain;charset=UTF-8',
        Data    =>  $args{message},
    );

    $msg->replace("X-Mailer", "SHM mailer");

    $msg->send(
        'smtp',
        $args{host},
        Debug => $args{debug} ? 1 : 0,
        #AuthUser => $user,
        #AuthPass => $pass,
        #SSL => 1,
        #Port => 465,
    );

    return SUCCESS, {
        server => {
            host => $args{host},
        },
        mail => {
            from => $args{from},
            to => $args{to},
            subject => $args{subject},
            template_id => $args{template_id},
        },
    };
}

1;
