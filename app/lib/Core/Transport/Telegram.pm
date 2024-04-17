package Core::Transport::Telegram;

use parent 'Core::Base';

use v5.14;
use Core::Base;
use Core::Const;
use Core::System::ServiceManager qw( get_service logger );
use LWP::UserAgent ();
use Core::Utils qw(
    switch_user
    encode_json
    decode_json
    passgen
    _utf8_off
    blessed
);

sub init {
    my $self = shift;
    my %args = (
        @_,
    );

    $self->{server} = 'https://api.telegram.org';
    $self->{lwp} = LWP::UserAgent->new(timeout => 10);
    $self->{webhook} = 0;
    $self->{deny_answer_direct} = 0;

    return $self;
}

sub send {
    my $self = shift;
    my $task = shift;

    my %server;
    if ( my $server = $task->server('telegram') ) {
        %server = $server->get;
    }

    my %settings = (
        %{ $server{settings} || {} },
        %{ $task->event_settings },
        %{ $task->settings },
    );

    my $message;
    if ( my $template = $self->template( $settings{template_id} ) ) {
        unless ( $template ) {
            return undef, {
                error => "template with id `$settings{template_id}` not found",
            }
        }

        $message = $template->parse(
            $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
            task => $task,
        );
    }
    return SUCCESS, { msg => "The template is empty, skip it." } unless $message;

    unless ( $self->chat_id ) {
        return SUCCESS, {
            error => "The user doesn't initialize the chat (chat_id not found). Skip it.",
        }
    }

    unless ( $self->token ) {
        return undef, {
            error => "telegram token not found. Please set it into config.telegram.token or template.settings.telegram.token",
        }
    }

    my $response = $self->sendMessage(
        text => $message,
    );

    if ( $response->is_success ) {
        logger->info(
            $response->decoded_content,
        );
        return SUCCESS, {
            message => 'successful',
        };
    } else {
        logger->error(
            $response->decoded_content,
        );
        # Always return SUCCESS. Skip broken messages
        return SUCCESS, {
            error => $response->decoded_content,
        };
    }
}

sub template {
    my $self = shift;
    my $template_id = shift;

    $self->{template_id} = $template_id if $template_id;
    return undef unless $self->{template_id};

    my $template = get_service('template', _id => $self->{template_id});
    return $template;
}

sub token {
    my $self = shift;

    my $token;
    $token = $self->template->get_settings->{telegram}->{token} if $self->template;
    $token ||= get_service('config')->data_by_name('telegram')->{token};

    unless ( $token ) {
        get_service('report')->add_error('Token not found');
        logger->error( 'Token not found' );
    }

    return $token;
}

sub chat_id {
    my $self = shift;

    my $chat_id = $self->message->{chat}->{id};
    $chat_id ||= $self->template->get_settings->{telegram}->{chat_id} if $self->template;
    $chat_id ||= $self->user->get_settings->{telegram}->{chat_id};

    unless ( $chat_id ) {
        get_service('report')->add_error('Chat_id not found');
        logger->error('Chat_id not found');
    }

    return $chat_id;
}

sub message {
    my $self = shift;

    if ( my $cb = $self->get_callback_query ) {
        return $cb->{message};
    }
    return $self->get_message || {};
}

sub parse_cmd {
    return split( /\s+/, shift );
}

sub get_cmd_args {
    my ( $cmd, @args ) = parse_cmd( shift );
    return (
        cmd => $cmd,
        args => \@args,
    );
}

sub cmd {
    my $self = shift;

    my ( $cmd, @args );

    if ( my $message = $self->get_message ) {
        $cmd = $message->{text};
        ( undef, @args ) = parse_cmd( $cmd );
        $cmd =~s/^\/(\w+)\s+.*$/\/$1/; # remove args from cmd if it starts from /
    } elsif ( my $cb = $self->get_callback_query ) {
        ( $cmd, @args ) = parse_cmd( $cb->{data} );
    }

    return $cmd, @args;
}

sub uploadDocument {
    my $self = shift;
    my %args = (
        data => undef,
        filename => 'file.conf',
        @_,
    );

    return $self->http(
        'sendDocument',
        content_type => 'form-data',
        data => {
            document => [ undef, delete $args{filename}, Content => delete $args{data} ],
            %args,
        }
    );
}

sub uploadPhoto {
    my $self = shift;
    my %args = (
        data => undef,
        filename => 'image.png',
        @_,
    );

    return $self->http(
        'sendPhoto',
        content_type => 'form-data',
        data => {
            photo => [ undef, delete $args{filename}, Content => delete $args{data} ],
            %args,
        }
    );
}

sub http {
    my $self = shift;
    my $url = shift;
    my %args = (
        method => 'post',
        content_type => 'application/json;  charset=utf-8',
        data => {},
        @_,
    );

    my $method = delete $args{method};
    my $content;

    if ( $args{content_type} eq 'form-data' ) {
        $content = [
            chat_id => $self->chat_id,
            %{ $args{data} },
        ];
    } else {
        if ( $self->{webhook} && !$self->{deny_answer_direct} ) {
            # Send answer directly
            my $response = {
                method => $url,
                chat_id => $self->chat_id,
                %{ $args{data} },
            };
            logger->dump('Telegram direct answer:', $response );
            return $response;
        } else {
            $content = encode_json({
                chat_id => $self->chat_id,
                %{ $args{data} },
            });
        }
    }

    my $response = $self->{lwp}->$method(
        sprintf('%s/bot%s/%s', $self->{server}, $self->token, $url ),
        Content_Type => $args{content_type},
        Content => $content,
    );

    logger->dump( $response->request );

    unless ( $response->is_success ) {
        logger->error(
            $response->decoded_content,
        );
    }
    return $response;
}

sub sendMessage {
    my $self = shift;
    my %args = (
        text => undef,
        parse_mode => 'HTML',
        disable_web_page_preview => 'True',
        @_,
    );

    $args{text} ||= '__no_text__';

    if ( length( $args{text} ) > 4096 ) {
        $args{text} = substr( $args{text}, 0, 4093 ) . '...';
    }

    return $self->http( 'sendMessage',
        data => \%args,
    );
}

sub deleteMessage {
    my $self = shift;
    my %args = (
        message_id => undef,
        @_,
    );

    return undef unless $args{message_id};

    return $self->http( 'deleteMessage',
        data => \%args,
    );
}

sub get_shm_login {
    return sprintf( "@%s", shift );
}

sub auth {
    my $self = shift;

    my $tg_user = $self->tg_user;
    return undef unless $tg_user;

    my $telegram_user_id = $tg_user->{id};
    my $username = $tg_user->{username};

    my ( $user ) = $self->user->_list(
        where => {
            -OR => [
                login => get_shm_login( $telegram_user_id ),
                $username ? ( sprintf('lower(%s->>"$.%s")', 'settings', 'telegram.login') => lc( $username ) ) : (),
                sprintf('%s->>"$.%s"', 'settings', 'telegram.user_id') => $telegram_user_id,
                sprintf('%s->>"$.%s"', 'settings', 'telegram.chat_id') => $self->chat_id, # for compatible with old versions of SHM
            ],
        },
        limit => 1,
    );
    return undef unless $user;

    switch_user( $user->{user_id} );

    $self->user->set_json(
        'settings', {
            telegram => {
                chat_id => $self->chat_id,
                user_id => $telegram_user_id,
            },
        },
    ) unless $user->{settings}->{telegram}->{user_id};

    return $user;
}

sub deleteMessage {
    my $self = shift;
    my %args = (
        message_id => undef,
        @_,
    );

    return $self->http( 'deleteMessage',
        data => \%args,
    );
}

sub tg_user {
    my $self = shift;

    my $user;
    if ( my $cb = $self->get_callback_query ) {
        $user = $cb->{from};
    } else {
        my $message = $self->get_message || {};
        if ( $message->{from}->{is_bot} ) {
            $user = $message->{chat};
        } else {
            $user = $message->{from};
        }
    }
    return $user;
}

sub process_message {
    my $self = shift;
    my %args = (
        template => 'telegram_bot',
        @_,
    );

    $self->{webhook} = 1;

    logger->debug('REQUEST:', \%args );
    $self->res( \%args );

    return undef if $self->message->{chat}->{type} ne 'private';

    my $template = $self->template( $args{template} );
    unless ( $template ) {
        logger->error("Template: '$args{template}' not exists");
        return undef;
    }

    if ( my $token = $template->get_settings->{telegram}->{token} ) {
        $self->token( $token );
    }

    my $user = $self->auth();

    if ( my $data = $args{pre_checkout_query} ) {
        return $self->http( 'answerPreCheckoutQuery',
            data => {
                pre_checkout_query_id => $data->{id},
                ok => $user ? 1 : 0,
            },
        );
    }

    return undef unless $self->token;

    my ( $cmd ) = $self->cmd;

    if ( $cmd ne '/register' ) {
        if ( !$user ) {
            logger->warning( 'USER_NOT_FOUND:', $self->tg_user);
            logger->warning( 'CMD:', $cmd );
            $cmd = 'USER_NOT_FOUND';
        } elsif ( $user->{block} ) {
            return $self->sendMessage(
                text => sprintf("You are blocked! (user_id: %s)", $user->{user_id} ),
            );
        }
    }

    if ( my $payment = $self->get_successful_payment ) {
        $self->user->payment(
            money => $payment->{total_amount} / 100,
            pay_system_id => 'telegram_bot',
            comment => $payment,
        );
        return {};
    }

    my $response = $self->exec_template(
        cmd => $cmd,
    );

    # Reply directly for only first response
    return get_last_object( $response );
}

sub get_last_object {
    my $obj = shift;

    if ( ref $obj eq 'ARRAY' ) {
        return get_last_object( $obj->[-1] );
    }
    return $obj;
}

sub exec_template {
    my $self = shift;
    my %args = (
        cmd => undef,
        args => undef,
        @_,
    );

    my ( $cmd, @args ) = $self->cmd;
    $args{cmd} ||= $cmd;
    $args{args} ||= \@args;

    my $obj = get_script( $self->template, $args{cmd},
        vars => {
            cmd => $args{cmd},
            message => $self->message,
            callback_query => $self->get_callback_query || {},
            args => $args{args},
        },
    );

    if ( my @errors = get_service('report')->errors ) {
        return $self->sendMessage(
            text => join('<br>', @errors),
        );
    }

    $self->{deny_answer_direct} += scalar @{ $obj };

    my @ret;
    for my $script ( @{ $obj } ) {
        logger->debug( 'Script:', $script );
        my $method = get_script_method( $script );

        $self->{deny_answer_direct}--;

        my $response;
        if ( $self->can( $method ) ) {
            $response = $self->$method( %{ $script->{ $method } || {} } );
        } else {
            $response = $self->http( $method,
                data => $script->{ $method } || {},
            );
        }

        if ( blessed $response ) {
            if ( $response->header('content-type') =~ /application\/json/i ) {
                push @ret, decode_json( $response->decoded_content );
            } else {
                push @ret, $response->decoded_content;
            }
        } else {
            push @ret, $response;
        }
    }

    return \@ret;
}

sub bot {
    my $self = shift;
    my $template_id = shift;
    my $cmd = shift;
    my $args = shift;

    my $template = $self->template( $template_id );
    unless ( $template ) {
        logger->debug('Template not exists: ', $template_id );
        return undef;
    }

    unless ( $self->chat_id ) {
        logger->debug('`telegram.chat_id` not defined' );
        return undef;
    }

    return $self->exec_template(
        cmd => $cmd,
        args => $args,
    );
}

sub get_script_method {
    my $data = shift;
    return ( keys %{ $data } )[0];
}

sub get_script {
    my $template = shift;
    my $cmd = shift;
    my %args = (
        vars => {},
        @_,
    );

    # Hack for working with Cyrillic commands
    _utf8_off( $cmd );

    my $data = $template->parse(
        START_TAG => '<%',
        END_TAG => '%>',
        vars => {
            cmd => $cmd,
        },
    );
    unless ( $data ) {
        logger->warning("Telegram bot: command $cmd not found or empty in ", $template->id );
        return undef;
    }

    my $ret = $template->parse(
        data => $data,
        %args,
    );
    unless ( $ret ) {
        logger->warning("Telegram bot: data is empty in ", $template->id );
        return undef;
    }

    return decode_json( "[ $ret ]" ) || [];
}

sub get_data_from_storage {
    my $self = shift;
    my $name = shift;

    my $data = get_service('storage')->read(
        name => $name,
        decode_json => 0,
    );
    unless ( $data ) {
        logger->error('Data with name', $name, 'not found');
        return undef;
    }

    return $data;
}

sub uploadDocumentFromStorage {
    my $self = shift;
    my %args = (
        name => undef,
        filename => undef,
        @_,
    );

    my $data = $self->get_data_from_storage( delete $args{name} );
    return undef unless $data;

    return $self->uploadDocument(
        data => $data,
        filename => delete $args{filename},
        %args,
    );
}

sub uploadPhotoFromStorage {
    my $self = shift;
    my %args = (
        name => undef,
        format => 'qr_code_png',
        @_,
    );

    my $data = $self->get_data_from_storage( delete $args{name} );
    return undef unless $data;

    if ( delete $args{format} eq 'qr_code_png' ) {
        $data = qx(echo "$data" | qrencode -t PNG -o -);
    }

    return $self->uploadPhoto(
        data => $data,
        %args,
    );
}

sub printQrCode {
    my $self = shift;
    my %args = (
        data => undef,
        format => 'qr_code_png',
        parameters => {},
        @_,
    );

    my $data = delete $args{data};
    return undef unless $data;

    if ( delete $args{format} eq 'qr_code_png' ) {
        $data = qx(echo "$data" | qrencode -t PNG -o -);
    }

    return $self->uploadPhoto(
        data => $data,
        %{ delete $args{parameters} || {} },
        %args,
    );
}

sub shmRegister {
    my $self = shift;
    my %args = (
        callback_data => undef,
        error => undef,
        partner_id => undef,
        @_,
    );

    if ( $self->auth ) {
        return $self->exec_template(
            get_cmd_args( $args{callback_data} ),
        );
    }

    my $tg_user = $self->tg_user;
    return undef unless $tg_user;

    my $telegram_user_id = $tg_user->{id};
    my $username = $tg_user->{username};

    my $user = get_service('user')->reg(
        login => get_shm_login( $telegram_user_id ),
        password => passgen(),
        full_name => sprintf("%s %s", $tg_user->{first_name}, $tg_user->{last_name} ),
        settings => {
            telegram => {
                $username ? ( login => $username ) : (),
                chat_id => $self->chat_id,
                user_id => $telegram_user_id,
            },
        },
        $args{partner_id} ? ( partner_id => $args{partner_id} ) : (),
    );

    if ( $user ) {
        $self->auth();
        return $self->exec_template(
            get_cmd_args( $args{callback_data} ),
        );
    } else {
        if ( $args{error} ) {
            return $self->sendMessage(
                text => $args{error},
            );
        }
    }
    return {};
}

sub shmServiceOrder {
    my $self = shift;
    my %args = (
        service_id => undef,
        callback_data => undef,
        cb_not_enough_money => undef,
        error => undef,
        @_,
    );

    my $us = get_service('service')->create(
        %args,
    );

    my $response;

    if ( $us ) {
        my $cmd = $us->is_paid ? $args{callback_data} : $args{cb_not_enough_money};
        $cmd ||= $args{callback_data};

        if ( $cmd ) {
            $response = $self->exec_template(
                get_cmd_args( $cmd ),
            );
        }
    } else {
        if ( $args{error} ) {
            return $self->sendMessage(
                text => $args{error},
            );
        }
    }

    return $response;
}

sub shmServiceDelete {
    my $self = shift;
    my %args = (
        usi => undef,
        callback_data => undef,
        error => undef,
        @_,
    );

    my $us = get_service('us')->id( $args{usi} );

    if ( $us ) {
        $us->delete();
        return $self->exec_template(
            get_cmd_args( $args{callback_data} ),
        );
    } else {
        if ( $args{error} ) {
            return $self->sendMessage(
                text => $args{error},
            );
        }
    }

    return {};
}

1;
