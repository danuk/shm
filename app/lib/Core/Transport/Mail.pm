package Core::Transport::Mail;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;

use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP qw();
use Try::Tiny;
use MIME::Base64 qw(encode_base64);

sub send {
    my $self = shift;
    my $task = shift;

    # First trying to determine server_id by group.
    my %server;
    if ( my $server_gid = $task->event->{server_gid} ) {
        my ( $server ) = get_service('ServerGroups', _id => $server_gid )->get_servers;
        %server = %{ $server };
    } elsif ( my $server = $task->server ) {
        %server = $server->get;
    } else {
        return SUCCESS, {
            error => sprintf( "Can't found server for server group", $server_gid ),
        }
    }

    my %settings = (
        %{ $server{settings} || {} },
        %{ $task->event->{settings} || {} },
    );

    my $config = get_service("config", _id => 'mail');
    $config = $config ? $config->get_data : {};

    $settings{from} //= $config->{from};
    unless ( $settings{from} ) {
        return SUCCESS, {
            error => "From undefined",
        }
    }

    $settings{from_name} //= $config->{from_name};
    $settings{subject} //= $config->{subject};
    $settings{to} //= delete $settings{bcc};

    if ( my $email = get_service('user')->emails ) {
        $settings{to} = $email;
    }
    unless ( $settings{to} ) {
        return SUCCESS, {
            error => "User email undefined",
        }
    }

    my $message;
    if ( $settings{template_id} || $settings{template_name} ) {

        my $template;

        if ( $settings{template_id} ) {
            $template = get_service('template', _id => $settings{template_id} );
            unless ( $template ) {
                return SUCCESS, {
                    error => "template with id `$settings{template_id}` not found",
                }
            }
        } elsif ( $settings{template_name} ) {
            $template = get_service('template')->id( $settings{template_name} );
            unless ( $template ) {
                return SUCCESS, {
                    error => "template with name `$settings{template_name}` not found",
                }
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

    my $email = Email::Simple->create(
        header => [
            From    => sprintf("=?UTF-8?B?%s?= <%s>", MIME::Base64::encode_base64($args{from_name}, ''), $args{from} ),
            To      => $args{to},
            Cc      => $args{cc} || "",
            BCc     => $args{bcc} || "",
            Subject => sprintf("=?UTF-8?B?%s?=", MIME::Base64::encode_base64($args{subject}, '')),
            Type    => 'text/plain;charset=UTF-8',
        ],
        body => $args{message},
    );

    my @err;
    my $status = SUCCESS;

    unless ( $ENV{SHM_TEST} ) {
        my ( $host, $port ) = split(/:/, $args{host} );

        my $ssl = 0;
        if ( $port == 465 ) {
            $ssl = 'ssl';
        } elsif ( $port == 587 ) {
            $ssl = 'starttls';
        }

        my $transport = Email::Sender::Transport::SMTP->new({
          host => $host,
          port => $port,
          ssl => $args{ssl} || $ssl,
          timeout => $args{timeout} || 30,
          $args{user} ? ( sasl_username => $args{user} ) : (),
          $args{password} ? ( sasl_password => $args{password} ) : (),
        });

        try {
            sendmail( $email, { transport => $transport });
        } catch {
            @err = split(/\n/, $_ );
            $status = FAIL;
        };
    }

    return $status, {
        server => {
            host => $args{host},
            # Never return id (it shouldn't be saved into user_services setting)
        },
        mail => {
            %args,
        },
        $err[0] ? ( error => $err[0] ) : (),
    };
}

1;
