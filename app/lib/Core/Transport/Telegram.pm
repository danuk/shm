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
);

sub init {
    my $self = shift;
    my %args = (
        @_,
    );

    $self->{server} = 'https://api.telegram.org';
    $self->{lwp} = LWP::UserAgent->new(timeout => 10);

    return $self;
}

sub send {
    my $self = shift;
    my $task = shift;

    delete $self->{chat_id};

    my %settings = (
        %{ $task->event->{settings} || {} },
    );

    my $message;
    if ( my $template = get_service('template', _id => $settings{template_id} ) ) {
        unless ( $template ) {
            return undef, {
                error => "template with id `$settings{template_id}` not found",
            }
        }

        if ( my $settings = $template->get_settings ) {
            $self->chat_id( $settings->{telegram}->{chat_id} );
            $self->token( $settings->{telegram}->{token} ) if $settings->{telegram}->{token};
        }

        $message = $template->parse(
            $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
            task => $task,
        );
    }
    return undef, { error => "message is empty" } unless $message;

    unless ( $self->chat_id ) {
        return SUCCESS, {
            error => "The user doesn't initialize the chat (chat_id not found). Skip it.",
        }
    }

    unless ( $self->token ) {
        return undef, {
            error => "telegram token not found. Please set it into config.telegram.token",
        }
    }

    return $self->sendMessage(
        text => $message,
    );
}

sub user {
    return get_service('user');
}

sub token {
    my $self = shift;
    my $token = shift;

    if ( $token ) {
        $self->{token} = $token;
    }

    $self->{token} ||= get_service('config')->data_by_name('telegram')->{token};
    logger->error( 'Token not found' ) unless $self->{token};

    return $self->{token};
}

sub chat_id {
    my $self = shift;
    my $chat_id = shift;

    if ( $chat_id ) {
        $self->{chat_id} = $chat_id;
    }

    unless ( $self->{chat_id} ) {
        if ( my $user = $self->user->get ) {
            $self->{chat_id} = $user->{settings}->{telegram}->{chat_id};
        }
    }

    return $self->{chat_id};
}

sub message {
    my $self = shift;
    my $message = shift;

    if ( $message ) {
        $self->{message} = $message;
    }

    return $self->{message};
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
            document => [ undef, $args{filename}, Content => $args{data} ],
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

    my $method = $args{method};
    my $content;

    if ( $args{content_type} eq 'form-data' ) {
        $content = [
            chat_id => $self->chat_id,
            %{ $args{data} },
        ];
    } else {
        $content = encode_json({
            chat_id => $self->chat_id,
            %{ $args{data} },
        });
    }

    my $response = $self->{lwp}->$method(
        sprintf('%s/bot%s/%s', $self->{server}, $self->token, $url ),
        Content_Type => $args{content_type},
        Content => $content,
    );

    logger->dump( $response->request );

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

sub sendMessage {
    my $self = shift;
    my %args = (
        text => undef,
        parse_mode => 'HTML',
        disable_web_page_preview => 'True',
        @_,
    );

    if ( length( $args{text} ) > 4096 ) {
        $args{text} = substr( $args{text}, 0, 4093 ) . '...';
    }

    return $self->http( 'sendMessage',
        data => \%args,
    );
}

sub auth {
    my $self = shift;
    my $message = shift;

    my $chat_id = $message->{chat}->{id};
    my $username = $message->{chat}->{username};

    return undef unless $chat_id;

    my ( $user ) = $self->user->_list(
        where => {
            -OR => [
                sprintf('%s->>"$.%s"', 'settings', 'telegram.chat_id') => $chat_id,
                $username ? ( sprintf('lower(%s->>"$.%s")', 'settings', 'telegram.login') => lc( $username ) ) : (),
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
            },
        },
    ) unless $user->{settings}->{telegram}->{chat_id};

    return $user;
}

sub deleteMessage {
    my $self = shift;
    my %args = (
        message_id => undef,
        @_,
    );

    $self->http( 'deleteMessage',
        data => \%args,
    );
}

sub process_message {
    my $self = shift;
    my %args = (
        message => undef,
        @_,
    );

    return undef unless $self->token;

    logger->debug('REQUEST:', \%args );

    my $message = $args{callback_query} ? $args{callback_query}->{message} : $args{message};
    $self->message( $message );

    $self->chat_id( $message->{chat}->{id} );

    my $query;
    if ( $args{message} ) {
        $query = $args{message}->{text};
    } elsif ( $args{callback_query} ) {
        $query = $args{callback_query}->{data};
    }

    my ( $cmd, @callback_args ) = split( /\s+/, $query );
    if ( $cmd=~s/^\|// ) {
        $cmd = join(' ', $cmd, @callback_args );
    }

    if ( $cmd ne '/register' ) {
        my $user = $self->auth( $message );
        if ( !$user ) {
            logger->warning( 'USER_NOT_FOUND. Chat_id', $message->{chat}->{id}, 'username:', $message->{chat}->{username} );
            $cmd = 'USER_NOT_FOUND';
        } elsif ( $user->{block} ) {
            return $self->sendMessage(
                text => sprintf("You are blocked! (user_id: %s)", $user->{user_id} ),
            );
        }
    }

    my $obj = get_script( $cmd,
        vars => {
            cmd => $cmd,
            message => $message,
            args => \@callback_args,
        },
    );

    if ( my @errors = get_service('report')->errors ) {
        return $self->sendMessage(
            text => join('<br>', @errors),
        );
    }

    for my $script ( @{ $obj } ) {
        logger->debug( 'Script:', $script );
        my $method = get_script_method( $script );

        my %allow_telegram_methods = (
            sendPhoto => 1,
            sendAudio => 1,
            sendDocument => 1,
            sendVideo => 1,
            sendAnimation => 1,
            sendVoice => 1,
            sendVideoNote => 1,
            sendMediaGroup => 1,
            sendLocation => 1,
            sendVenue => 1,
            sendContact => 1,
            sendPoll => 1,
            sendDice => 1,
            sendChatAction => 1,
            deleteMessage => 1,
        );

        if ( $self->can( $method ) ) {
            $self->$method( %{ $script->{ $method } || {} } );
        } elsif ( $allow_telegram_methods{ $method } ) {
            $self->http( $method,
                data => $script->{ $method } || {},
            );
        } else {
            logger->error("Method $method not exists");
            next;
        }
    }

    return 1;
}

sub get_script_method {
    my $data = shift;
    return ( keys %{ $data } )[0];
}

sub get_script {
    my $cmd = shift;
    my %args = (
        vars => {},
        @_,
    );

    my $template = get_service('template', _id => 'telegram_bot');
    unless ( $template ) {
        logger->error("Telegram bot: telegram_bot not exists");
        return [];
    }

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
        logger->warning("Telegram bot: command $cmd not found or empty in telegram_bot");
        return undef;
    }

    my $ret = $template->parse(
        data => $data,
        %args,
    );
    unless ( $ret ) {
        logger->warning("Telegram bot: data is empty in telegram_bot");
        return undef;
    }

    return decode_json( "[ $ret ]" ) || [];
}

sub get_data_from_storage {
    my $self = shift;
    my $name = shift;

    my $data = get_service('storage')->list_for_api( name => $name );
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

    my $data = $self->get_data_from_storage( $args{name} );
    return undef unless $data;

    return $self->uploadDocument(
        data => $data,
        filename => $args{filename},
    );
}

sub uploadPhotoFromStorage {
    my $self = shift;
    my %args = (
        name => undef,
        format => 'qr_code_png',
        @_,
    );

    my $data = $self->get_data_from_storage( $args{name} );
    return undef unless $data;

    if ( $args{format} eq 'qr_code_png' ) {
        $data = qx(echo "$data" | qrencode -t PNG -o -);
    }

    return $self->uploadPhoto(
        data => $data,
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

    my $data = $args{data};
    return undef unless $data;

    if ( $args{format} eq 'qr_code_png' ) {
        $data = qx(echo "$data" | qrencode -t PNG -o -);
    }

    return $self->uploadPhoto(
        data => $data,
        %{ $args{parameters} || {} },
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

    return 1 if $self->auth( $self->message );

    my $username = $self->message->{chat}->{username};
    my $chat_id = $self->message->{chat}->{id};

    my $user = get_service('user')->reg(
        login => sprintf( "@%s", $chat_id ),
        password => passgen(),
        full_name => sprintf("%s %s", $self->message->{chat}->{first_name}, $self->message->{chat}->{last_name} ),
        settings => {
            telegram => {
                $username ? ( login => $username ) : (),
                chat_id => $chat_id,
            },
        },
        $args{partner_id} ? ( partner_id => $args{partner_id} ) : (),
    );

    if ( $user ) {
        my $message = $self->message;
        $message->{text} = $args{callback_data};
        return $self->process_message(
            message => $message,
        );
    } else {
        if ( $args{error} ) {
            return $self->sendMessage(
                text => $args{error},
            );
        }
    }

    return 1;
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

    # Save changes for next telegram actions
    $self->commit;
    $self->user->reload;

    if ( $us ) {
        my $message = $self->message;

        if ( $args{cb_not_enough_money} && !$us->is_paid ) {
            $args{callback_data} = $args{cb_not_enough_money};
        }

        $message->{text} = $args{callback_data};
        return $self->process_message(
            message => $message,
        );
    } else {
        if ( $args{error} ) {
            return $self->sendMessage(
                text => $args{error},
            );
        }
    }

    return 1;
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
        my $message = $self->message;
        $message->{text} = $args{callback_data};
        return $self->process_message(
            message => $message,
        );
    } else {
        if ( $args{error} ) {
            return $self->sendMessage(
                text => $args{error},
            );
        }
    }

    return 1;
}

1;
