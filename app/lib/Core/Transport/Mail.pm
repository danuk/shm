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
use Core::Utils qw(
    is_email
);

sub send {
    my $self = shift;
    my $task = shift;

    # First trying to determine server_id by group.
    my %server;
    if ( my $server_gid = $task->event->{server_gid} ) {

        my $sg = get_service('ServerGroups', _id => $server_gid );
        unless ( $sg ) {
            return undef, {
                error => sprintf( "Can't find server group", $server_gid ),
            };
        }

        my ( $server ) = $sg->get_servers;
        unless ( $server ) {
            return undef, {
                error => sprintf( "Can't find server for server group", $server_gid ),
            };
        }

        %server = %{ $server };
    } elsif ( my $server = $task->server ) {
        %server = $server->get;
    } else {
        return undef, {
            error => sprintf( "Can't find server for server group", $server_gid ),
        }
    }

    my %settings = (
        %{ $server{settings} || {} },
        %{ $task->event_settings },
        %{ $task->settings },
    );

    my $config = get_service("config", _id => 'mail');
    $config = $config ? $config->get_data : {};

    $settings{from} //= $config->{from};
    unless ( $settings{from} ) {
        return undef, {
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
            error => "User email undefined. For test email set `bcc` in server",
        }
    }

    my $message;
    if ( $settings{template_id} || $settings{template_name} ) {
        my $template;
        if ( $settings{template_id} ) {
            $template = get_service('template', _id => $settings{template_id} );
            unless ( $template ) {
                return undef, {
                    error => "template with id `$settings{template_id}` not found",
                }
            }
        } elsif ( $settings{template_name} ) {
            $template = get_service('template')->id( $settings{template_name} );
            unless ( $template ) {
                return undef, {
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
    }

    $message ||= delete $settings{message};
    return SUCCESS, { msg => "The message is empty, skip it." } unless $message;

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

    return undef, {
        error => "Incorrect FROM address: $args{from}",
    } unless is_email( $args{from} );

    return undef, {
        error => "Incorrect email address: $args{to}",
    } unless is_email( $args{to} );

    if ( my $email = $args{cc} ) {
        return undef, {
            error => "Incorrect CC address: $email",
        } unless is_email( $email );
    }

    if ( my $email = $args{bcc} ) {
        return undef, {
            error => "Incorrect BCc address: $email",
        } unless is_email( $email );
    }

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

    my $err;
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
          port => $port || 25,
          ssl => $args{ssl} || $ssl,
          timeout => $args{timeout} || 30,
          $args{user} ? ( sasl_username => $args{user} ) : (),
          $args{password} ? ( sasl_password => $args{password} ) : (),
        });

        try {
            sendmail( $email, { transport => $transport });
        } catch {
            my @err = split(/\n/, $_ );
            my @ret;
            while ( my $s = shift @err ) {
                push @ret, $s;
            };
            $err = join('\n', @ret );
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
        $err ? ( error => $err ) : (),
    };
}

1;
