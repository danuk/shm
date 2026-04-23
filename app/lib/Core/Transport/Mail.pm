package Core::Transport::Mail;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;

use threads; # to prevent the message on aarch64 (ARM): Can't locate object method "tid" via package "threads"
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP qw();
use Try::Tiny;
use MIME::Base64 qw(encode_base64);
use Core::Utils qw(
    is_email
    encode_utf8
);

sub init {
    my $self = shift;
    my %args = @_;

    $self->{$_} = $args{$_} for keys %args;
    $self->{server_gid} //= 6; #Mail Group

    return $self;
}

sub setup { shift->init( get_smart_args @_ ) };

sub send {
    my $self = shift;
    my $message = shift;
    my %args = (
        get_smart_args( @_ ),
    );

    my $server_group = get_service('ServerGroups', _id => $self->{server_gid} );
    unless ( $server_group ) {
        $self->logger->error("Server group not exists:", $self->{server_gid});
        return undef;
    }

    my ( $server ) = $server_group->get_servers();
    unless ( $server ) {
        $self->logger->error("Server not found in server group:", $self->{server_gid});
        return undef;
    }

    my $settings = delete $server->{settings} || {};

    my %data = (
        %{ $server },
        %{ $settings },
        %args,
    );

    my ( $status, $response ) = $self->send_mail(
        host => $self->{host},
        from => $self->{from},
        to => $self->{to} || $self->user->email,
        subject => $self->{subject} || 'SHM',
        from_name => $self->{from_name} || 'SHM',
        content_type => $self->{content_type},
        message => $message,
        %data,
    );

    if ( ref $response eq 'HASH' ) {
        if ( $response->{error} ) {
            $self->logger->error( $response->{error} );
        } else {
            $self->logger->debug( $response );
        }
    }

    return $status, $response;
}

sub task_send {
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

    $settings{from} ||= $config->{from};
    unless ( $settings{from} ) {
        return undef, {
            error => "From undefined",
        }
    }

    $settings{from_name} ||= $config->{from_name};
    $settings{subject} ||= $config->{subject};
    $settings{to} ||= delete $settings{bcc} || $self->user->email;

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
        content_type => undef,
        @_,
    );

    $args{content_type} ||= 'text/plain';

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

    %args = %{ encode_utf8( \%args ) };

    my $email = Email::Simple->create(
        header => [
            From    => sprintf("=?UTF-8?B?%s?= <%s>", MIME::Base64::encode_base64($args{from_name}, ''), $args{from} ),
            To      => $args{to},
            Cc      => $args{cc} || "",
            BCc     => $args{bcc} || "",
            Subject => sprintf("=?UTF-8?B?%s?=", MIME::Base64::encode_base64($args{subject}, '')),
            'Content-Type' => "$args{content_type}; charset=UTF-8",
            'Content-Transfer-Encoding' => 'base64',
        ],
        body => MIME::Base64::encode_base64($args{message}, ""),
    );

    my $err;
    my $status = SUCCESS;

    unless ( $ENV{SHM_TEST} ) {
        my ( $host, $port ) = split(/:/, $args{host} );

        # Empty string means "not set" (common for UI forms); let port defaults decide.
        my $ssl = defined $args{ssl} && $args{ssl} ne '' ? $args{ssl} : undef;
        my $starttls = defined $args{starttls} && $args{starttls} ne '' ? $args{starttls} : undef;

        # Email::Sender::Transport::SMTP expects TLS mode via `ssl`:
        #   ssl => 'ssl'      for direct TLS
        #   ssl => 'starttls' for STARTTLS upgrade
        my $tls_mode;
        if ( defined $ssl ) {
            $tls_mode = $ssl ? 'ssl' : '';
        } elsif ( defined $starttls ) {
            $tls_mode = $starttls ? 'starttls' : '';
        }

        # Auto-select TLS mode by port only when no explicit flags were provided.
        unless ( defined $ssl || defined $starttls ) {
            if ( $port == 465 ) {
                $tls_mode = 'ssl';
            } elsif ( $port == 587 || $port == 25 ) {
                $tls_mode = 'starttls';
            }
        }

        my %smtp_params = (
            host    => $host,
            port    => $port || 25,
            timeout => $args{timeout} || 30,
            $tls_mode ? ( ssl => $tls_mode ) : (),
        );

        # Добавляем авторизацию, если есть
        $smtp_params{sasl_username} = $args{user}     if $args{user};
        $smtp_params{sasl_password} = $args{password} if $args{password};

        my $transport = Email::Sender::Transport::SMTP->new( \%smtp_params );

        try {
            sendmail( $email, { transport => $transport });
        } catch {
            my @err = split(/\r?\n/, $_ );
            my @ret;
            while ( my $s = shift @err ) {
                push @ret, $s;
            };
            $err = join(' ', @ret );
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
