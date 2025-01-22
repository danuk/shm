package Core::Transport::Telegram;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;
use Core::System::ServiceManager qw( get_service logger );
use LWP::UserAgent ();
use Core::Utils qw(
    switch_user
    encode_json
    encode_json_utf8
    encode_utf8
    decode_json
    decode_json_utf8
    passgen
    blessed
    now
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

sub user_tg_settings {
    my $self = shift;
    my %args = (
        get_smart_args(@_),
    );

    my $data = $self->user->settings->{telegram} || {};

    if ( my $profile = $data->{ $self->profile } ) {
        $data = { %{$data}, %{$profile}  };
    }

    return $data || {};
}

sub profile {
    my $self = shift;
    my $name = shift;

    if ($name) {
        $self->{profile} = $name;
    }

    return $self->{profile} || 'telegram_bot';
}

sub send {
    my $self = shift;
    my $task = shift;

    $self->{deny_answer_direct} = 1;

    my %server;
    if ( my $server = $task->server('telegram') ) {
        %server = $server->get;
    }

    my %settings = (
        %{ $server{settings} || {} },
        %{ $task->event_settings },
        %{ $task->settings },
    );

    my $template = $self->template( $settings{template_id} );
    unless ( $template ) {
        return undef, {
            error => "template with id `$settings{template_id}` not found",
        }
    }

    if ( my $tpl_settings_tg = $template->settings->{telegram} ) {
        for ( keys %{ $tpl_settings_tg } ) {
            $settings{telegram}->{$_} = $tpl_settings_tg->{$_};
        }
    }

    $self->profile( $settings{telegram}{profile} );

    if ( $self->user_tg_settings->{status} eq 'kicked' || $self->user_tg_settings->{status} eq 'left' ) {
        return SUCCESS, { msg => "Telegram user is not member now, skip it." };
    }

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

    my $message = $template->parse(
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        task => $task,
    );
    return SUCCESS, { msg => "The template is empty, skip it." } unless $message;

    my $response;
    if ( my $method = $settings{telegram}{method} ) {
        my $data = decode_json( $message );
        unless ( $data ) {
            return undef, {
               error => "Message is not JSON",
            }
        }

        $response = $self->http( $method,
            data => $data,
            $settings{telegram}{content_type} ? (content_type => $settings{telegram}{content_type}) : (),
        );
    } else {
        $response = $self->sendMessage(
            text => $message,
            parse_mode => $settings{parse_mode} || 'HTML',
        );
    }

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
    unless ( $token ) {
        my $config = get_service('config')->data_by_name('telegram');
        $token ||= $config->{ $self->profile }->{token};
        $token ||= $config->{token};
    }

    unless ( $token ) {
        get_service('report')->add_error('Token not found');
        logger->error( 'Token not found' );
    }

    return $token;
}

sub chat_id {
    my $self = shift;

    my $chat_id = $self->message->{chat}->{id};
    $chat_id ||= $self->get_my_chat_member->{chat}->{id} if $self->get_my_chat_member;
    $chat_id ||= $self->template->get_settings->{telegram}->{chat_id} if $self->template;
    $chat_id ||= $self->user_tg_settings->{chat_id};

    unless ( $chat_id ) {
        get_service('report')->add_error('Chat_id not found');
        logger->warning('Chat_id not found');
    }

    return $chat_id;
}

sub start_args {
    my $self = shift;
    my %args = (
        @_,
    );

    if ( %args ) {
        $self->{start_args} = \%args;
    }

    return %{ $self->{start_args} || {} };
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
    my $data = shift;
    my %args = (
        filename => 'file.conf',
        @_,
    );

    encode_utf8( \%args );

    return $self->http(
        'sendDocument',
        content_type => 'form-data',
        data => {
            document => [ undef, delete $args{filename}, Content =>  $data ],
            %args,
        }
    );
}

sub uploadPhoto {
    my $self = shift;
    my $data = shift;
    my %args = (
        filename => 'image.png',
        @_,
    );

    encode_utf8( \%args );

    return $self->http(
        'sendPhoto',
        content_type => 'form-data',
        data => {
            photo => [ undef, delete $args{filename}, Content => $data ],
            %args,
        }
    );
}

sub http {
    my $self = shift;
    my $url = shift;
    my %args = (
        method => 'post',
        content_type => 'application/json; charset=utf-8',
        data => {},
        chat_id => $self->chat_id,
        @_,
    );

    my $method = delete $args{method};
    my $content;

    if ( $args{content_type} eq 'form-data' ) {
        my %data = %{ $args{data} };
        for my $k ( keys %data ) {
            next if $k eq 'document' || $k eq 'photo';
            if ( ref $data{$k} ) {
                $data{$k} = encode_json( $data{$k} );
            }
        }

        $content = [
            chat_id => $args{chat_id},
            %data,
        ];
    } else {
        if ( $self->{webhook} && !$self->{deny_answer_direct} ) {
            # Send answer directly
            my $response = {
                method => $url,
                chat_id => $args{chat_id},
                %{ $args{data} },
            };
            logger->dump('Telegram direct answer:', $response );
            return $response;
        } else {
            $content = encode_json_utf8({
                chat_id => $args{chat_id},
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
    my $full_name = sprintf("%s %s", $tg_user->{first_name}, $tg_user->{last_name} );

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

    return $self->user unless $self->chat_id;

    $self->user->set( last_login => now );
    $self->user->set_json(
        'settings', {
            telegram => {
                username => $tg_user->{username},
                first_name => $tg_user->{first_name},
                last_name => $tg_user->{last_name},
                language_code => $tg_user->{language_code},
                is_premium => $tg_user->{is_premium},
                $self->profile => {
                    chat_id => $self->chat_id,
                },
            },
        },
    );

    return $self->user;
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
    } elsif ( my $message = $self->get_pre_checkout_query ) {
        $user = $message->{from};
    } elsif ( my $member = $self->get_my_chat_member ) {
        $user = $member->{from};
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

    $self->profile( $args{template} );

    $self->{webhook} = 1;
    $self->{deny_answer_direct} = 0;

    logger->debug('REQUEST:', \%args );
    $self->res( \%args );

    my $template = $self->template( $args{template} );
    unless ( $template ) {
        logger->error("Template: '$args{template}' not exists");
        return undef;
    }

    my $user = $self->auth();

    if ( my $data = $self->get_pre_checkout_query ) {
        $self->{deny_answer_direct} = 1;
        return $self->http( 'answerPreCheckoutQuery',
            data => {
                pre_checkout_query_id => $data->{id},
                ok => $user ? 1 : 0,
            },
        );
    }

    if ( my $payment = $self->message->{successful_payment} ) {
        $user->payment(
            money => $payment->{total_amount},
            currency => $payment->{currency},
            uniq_key => $payment->{telegram_payment_charge_id},
            pay_system_id => 'telegram_bot',
            comment => $payment,
        );
        return {};
    }

    if ( my $my_chat_member = $self->get_my_chat_member ) {
        return {} unless $user;
        $user->set_settings({
            telegram => {
                $self->profile => {
                    status => $my_chat_member->{new_chat_member}->{status},
                },
            }
        });
        return {};
    }

    return undef if $self->message->{chat}->{type} ne 'private';
    return undef unless $self->token;

    my ( $cmd, @args ) = $self->cmd;

    if ( $cmd eq '/start' && $args[0] ) {
        use MIME::Base64;
        use URI::Escape;
        my %start_args;
        for my $pair ( split /&/, MIME::Base64::decode_base64url( $args[0] ) ) {
            my ( $key, $value ) = split ( /=/, $pair );
            $start_args{ $key } = uri_unescape( $value ) if defined $key && defined $value;
            $self->start_args( %start_args );
        }
    }

    if ( $cmd ne '/register' ) {
        if ( !$user ) {
            logger->warning( 'USER_NOT_FOUND:', $self->tg_user);
            logger->warning( 'CMD:', $cmd );
            $cmd = 'USER_NOT_FOUND';
        } elsif ( $user->is_blocked ) {
            return $self->sendMessage(
                text => sprintf("You are blocked! (user_id: %s)", $user->id ),
            );
        }
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

    my %start_args = $self->start_args;

    my $obj = $self->get_script( $self->template, $args{cmd},
        vars => {
            cmd => $args{cmd},
            message => $self->message,
            callback_query => $self->get_callback_query || {},
            args => $args{args},
            start_args => \%start_args,
        },
    );

    return [] unless $obj;

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
    my $self = shift;
    my $template = shift;
    my $cmd = shift;
    my %args = (
        vars => {},
        @_,
    );

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
        task => $self->{task} || undef,
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
        $data,
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
        $data,
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
        $data,
        %{ delete $args{parameters} || {} },
        %args,
    );
}

sub shmRedirectCallback {
    my $self = shift;
    my %args = (
        callback_data => undef,
        @_,
    );

    return $self->exec_template(
        get_cmd_args( $args{callback_data} ),
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

    my %start_args = $self->start_args;
    $args{partner_id} //= $start_args{pid};

    my $telegram_user_id = $tg_user->{id};

    my $user = $self->user->reg(
        login => get_shm_login( $telegram_user_id ),
        password => passgen(),
        full_name => sprintf("%s %s", $tg_user->{first_name}, $tg_user->{last_name} ),
        settings => {
            telegram => {
                user_id => $telegram_user_id,
                username => $tg_user->{username},
                first_name => $tg_user->{first_name},
                last_name => $tg_user->{last_name},
                language_code => $tg_user->{language_code},
                is_premium => $tg_user->{is_premium},
                $self->profile => {
                    chat_id => $self->chat_id,
                    status => 'member',
                },
            },
        },
        $args{partner_id} ? ( partner_id => $args{partner_id} ) : (),
    );

    if ( $user ) {
        $self->auth();
        if ( %start_args ) {
            my %utm;
            for ( keys %start_args ) {
                $utm{ $_ } = $start_args{ $_ } if $_ =~ /^utm_/;
            }
            $self->user->set_settings({ utm => \%utm }) if %utm;
        };
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
        end_date => undef,
        callback_data => undef,
        cb_not_enough_money => undef,
        cb_already_exists => undef,
        error => undef,
        get_smart_args( @_ ),
    );

    my @us_list = $self->user->us->list;
    my $us_count_before = scalar @us_list;

    my $us = $self->user->us->create( %args );

    my $response;

    if ( $us ) {
        my $cmd = $us->is_paid ? $args{callback_data} : $args{cb_not_enough_money};
        $cmd ||= $args{callback_data};

        if ( $args{cb_already_exists} ) {
            my @us_list = $self->user->us->list;
            my $us_count_after = scalar @us_list;
            if ( $us_count_before == $us_count_after ) {
                $cmd = $args{cb_already_exists};
            }
        }

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

sub webapp_auth {
    my $self = shift;
    my %args = (
        uid => undef,
        initData => undef,
        profile => 'telegram_bot',
        @_,
    );

    unless ( $args{initData} && $args{uid} ) {
        get_service('report')->add_error("bad request");
        return undef;
    }

    if ( $self->user->id($args{uid})) {
        switch_user( $args{uid} );
    } else {
        logger->error("Telegram WebApp auth error: user not found");
        get_service('report')->add_error("bad request");
        return undef;
    }

    $self->profile( $args{profile} );

    my %in = CGI->new( $args{initData} )->Vars();

    my $user = decode_json_utf8( $in{user} );
    if ( $user->{id} ne $self->user_tg_settings->{user_id} ) {
        logger->error("Telegram WebApp auth error: user_id doesn't match");
        get_service('report')->add_error("bad request");
        return undef;
    }

    my $hash = delete $in{hash};
    my @arr = map( "$_=$in{$_}", sort { $a cmp $b } keys %in );
    my $data_check_string = join("\n", @arr );

    use Digest::SHA qw(hmac_sha256 hmac_sha256_hex);
    my $secret_key = hmac_sha256( $self->token, "WebAppData" );
    my $hex = hmac_sha256_hex( $data_check_string, $secret_key);

    unless ( $hex eq $hash ) {
        logger->error('Telegram WebApp auth error');
        get_service('report')->add_error("invalid credentails");
        return undef;
    }

    return {
        session_id => $self->srv('sessions')->add(),
    };
}

1;
