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
    encode_utf8
    encode_json
    decode_json
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
    $self->{deny_answer_direct} = 1;

    return $self;
}

sub config {
    return get_service('config')->data_by_name('telegram') || {};
}

sub user_tg_settings {
    my $self = shift;

    return $self->{user_tg_settings} if $self->{user_tg_settings};

    my $data = $self->user->settings->{telegram} || {};
    my $profile = $data->{ $self->{profile} } || {};

    $data = { %{$data}, %{$profile} };

    return $self->{user_tg_settings} = $data || {};
}

# methods for Templates
sub settings { shift->user_tg_settings };
sub login { shift->user_tg_settings->{username} };
sub username { shift->user_tg_settings->{username} };

# устанавливает указанный профиль: token & chat_id
# Не устанавливаем chat_id, если он был установлен ранее,
# это нужно для новых клиентов и возможности переопределения
sub profile {
    my $self = shift;
    my $name = shift;

    return $self->{profile} unless $name;

    my $config = $self->config;

    $self->{profile} = $name;

    if ( my $profile = $config->{ $name } ) {
        $self->{token} = $profile->{token};
        $self->{chat_id} ||= $profile->{chat_id} if $profile->{chat_id};
    } else {
        $self->{token} = $config->{token}; # for backward compatible
    }

    $self->{chat_id} ||= $self->user_tg_settings->{chat_id};

    # всегда возвращаем себя, это нужно для: user.telegram.profile(NAME).send()
    return $self;
}

sub user_profiles {
    my $self = shift;

    my @profiles;
    my $user_profiles = $self->user->settings->{telegram} || {};

    if ( my $profile = $self->{profile} ) {
        push @profiles, $profile;
    } else {
        for ( keys %$user_profiles ) {
            push @profiles, $_ if ref $user_profiles->{$_} eq 'HASH';
        }
    }

    unless ( scalar @profiles ) { # for backward compatible
        if ( exists $user_profiles->{chat_id} ) {
            push @profiles, 'telegram_bot';
        }
    }

    return wantarray ? @profiles : \@profiles;
}

sub task_send {
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

    my $tpl_settings_tg = $template->settings->{telegram} || {};
    $self->{profile} = $tpl_settings_tg->{profile} if $tpl_settings_tg->{profile};

    # Override chat_id if present (for backward compatible)
    $self->{chat_id} = $tpl_settings_tg->{chat_id} if $tpl_settings_tg->{chat_id};

    unless ( scalar $self->user_profiles() ) {
        return SUCCESS, {
            error => "Пользователь ещё не добавил этого бота",
        }
    }

    my $message = $template->parse(
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        task => $task,
        vars => {
            tg => sub { $self },
            tg_api => sub{ $self->tg_api( @_ ) },
            response => sub { $self->{response} },
        },
    );
    return SUCCESS, { msg => "Шаблон не содержит данных" } unless $message;

    if ( my $tg_method = $tpl_settings_tg->{raw} ) {
        my $json = decode_json( $message );
        $message = $json if ref $json eq 'HASH' || ref $json eq 'ARRAY';
    } elsif ( my $tg_method = $tpl_settings_tg->{method} ) {
        my $json = decode_json( $message );
        if ( ref $json eq 'HASH' ) {
            $message = {
                $tg_method => $json
            }
        }
    }

    my @ret = $self->send( $message );

    if ( my $error = $ret[0]->{error} ) {
        if ( ref $error eq 'HASH' ) {
            # http was executed
            return SUCCESS, $ret[0] if $error->{error_code} == 403; # skip
            return undef, $ret[0] if $error->{error_code} == 400; # bad request
            return undef, $ret[0] if $error->{error_code} == 404; # method not found
            return FAIL, $ret[0]; # retry
        } else {
            # chat_id or token not found, etc...
            return SUCCESS, $ret[0]; # skip
        }
    } else {
        return SUCCESS, $ret[0];
    }
}

sub send {
    my $self = shift;
    my $data = shift;
    my %settings = (
        parse_mode => 'HTML',
        get_smart_args(@_),
    );

    my @ret;
    my @profiles = $self->user_profiles();
    for my $profile ( @profiles ) {
        $self->profile( $profile );

        unless ( $self->{chat_id} ) {
            push @ret, { error => "chat_id не найден", profile => $profile };
            next;
        }

        unless ( $self->{token} ) {
            push @ret, { error => "token не найден", profile => $profile };
            next;
        }

        if ( $self->user_tg_settings->{status} eq 'kicked' || $self->user_tg_settings->{status} eq 'left' ) {
            push @ret, { msg => "Пользователь заблокировал Telegram bot", profile => $profile };
            next;
        }

        my $response;
        if ( ref $data ) {
            my @arr;
            if ( ref $data eq 'HASH' ) {
                push @arr, $data;
            } elsif ( ref $data eq 'ARRAY' ) {
                @arr = @$data;
            } else {
                report->error( 'unkonwn type of data:', ref $data );
                return { error => 'unknown type of data' };
            }

            for ( @arr ) {
                unless (ref $_ eq 'HASH') {
                    report->error( 'unkonwn type of data:', ref $_ );
                    next;
                }
                my ( $method ) = keys %{$_};
                $response = $self->http( $method,
                    data => $_->{ $method },
                    %settings,
                );
                unless ( $response->is_success ) {
                    report->error( decode_json( $response->decoded_content ) );
                    last;
                }
            }
        } else {
            $response = $self->sendMessage(
                text => $data,
                %settings,
            );
        }

        my $message = decode_json( $response->decoded_content );
        if ( $response->is_success ) {
            logger->info( $message );
            push @ret, { message => 'successful', profile => $profile, response => $message };
            $self->{response} = $message;
        } else {
            logger->error( $message );
            push @ret, {
                error => $message,
                profile => $profile,
                request => decode_json( $response->request->content ),
            };
        }
    }
    return @ret;
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

    $self->profile( $template_id ) unless $self->{profile};

    unless ( $self->chat_id ) {
        logger->debug('chat_id не найден' );
        return undef;
    }

    return $self->exec_template(
        cmd => $cmd,
        args => $args,
    );
}

sub template {
    my $self = shift;
    my $template_id = shift;

    $self->{template_id} = $template_id if $template_id;
    return undef unless $self->{template_id};

    my $template = get_service('template', _id => $self->{template_id});
    return $template;
}

sub token { shift->{token} };
sub chat_id { shift->{chat_id} };

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

    unless ( $self->token && $self->chat_id ) {
        logger->error('token or chat_id not defined');
        return {};
    }

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
            $content = encode_json({
                chat_id => $args{chat_id},
                %{ $args{data} },
            });
        }
    }

    my $response = $self->{lwp}->$method(
        sprintf('%s/bot%s/%s', $self->{server}, $self->token, $url ),
        Content_Type => $args{content_type},
        Content => encode_utf8( $content ),
    );

    logger->dump('Send to TG API', $response->request );
    logger->dump('Answer from TG API', $response->decoded_content );

    unless ( $response->is_success ) {
        my $message = $response->decoded_content;
        logger->error( $message );

        if ( $response->code == 403 ) {
            $self->user->set_settings({
                telegram => {
                    $self->{profile} => {
                        status => 'kicked',
                    },
                }
            });
        }
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
                sprintf('%s->>"$.%s"', 'settings', 'telegram.user_id') => $telegram_user_id,
                login => get_shm_login( $telegram_user_id ),
                $username ? ( sprintf('lower(%s->>"$.%s")', 'settings', 'telegram.username') => lc( $username ) ) : (),
                sprintf('%s->>"$.%s"', 'settings', 'telegram.chat_id') => $self->chat_id, # for backward compatible
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
                login => $tg_user->{username}, # for backward compatible
                username => $tg_user->{username},
                first_name => $tg_user->{first_name},
                last_name => $tg_user->{last_name},
                language_code => $tg_user->{language_code},
                is_premium => $tg_user->{is_premium},
                chat_id => $self->chat_id, # for backward compatible
                $self->{profile} => {
                    chat_id => $self->chat_id,
                },
            },
        },
    ) if $self->message->{chat}->{type} eq 'private';

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
        tg_profile => undef, # you can set it in the webhook
        template => 'telegram_bot',
        @_,
    );

    $self->{webhook} = 1;
    $self->{deny_answer_direct} = 1;

    logger->debug('REQUEST from Telegram:', \%args );
    $self->res( \%args );

    # Set the chat_id from the message because it is unknown to new clients
    my $chat_id = $self->message->{chat}->{id};
    $chat_id ||= $self->get_pre_checkout_query->{from}->{id} if $self->get_pre_checkout_query;
    $chat_id ||= $self->get_my_chat_member->{chat}->{id} if $self->get_my_chat_member;
    $self->{chat_id} = $chat_id if $chat_id;

    $self->profile( $args{tg_profile} || $args{template} );

    my $template = $self->template( $args{template} );
    unless ( $template ) {
        return {
            method => 'sendMessage',
            chat_id => $self->{chat_id},
            parse_mode => 'MarkdownV2',
            text => sprintf("Ошибка: шаблон `%s` не найден",
                $args{template},
            )
        }
    }

    unless ( $self->{token} ) {
        return {
            method => 'sendMessage',
            chat_id => $self->{chat_id},
            parse_mode => 'MarkdownV2',
            text => sprintf("Ошибка: [token](%s) не найден\nПрофиль: `%s`\nchat\\_id: `%s`",
                'https://docs.myshm.ru/docs/setup/servers/transport/telegram/',
                $self->profile,
                $chat_id,
            )
        }
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

    my $exchange_rate;
    if ( my $payment = $self->message->{successful_payment} ) {
        my $money = $payment->{total_amount};
        if ( $payment->{currency} eq 'XTR' ) {
            if ( $exchange_rate = $self->config->{xtr_exchange_rate} ) {
                $money = $money * $exchange_rate;
            }
        }

        $user->payment(
            money => $money,
            exchange_rate => $exchange_rate,
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
                $self->{profile} => {
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

    return {};
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

    my $obj = $self->get_script( $self->template, %args );
    return [] unless $obj;

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

sub tg_api {
    my $self = shift;
    my %args = (
        get_smart_args( @_ ),
    );

    my ($method) = keys %args;
    return undef unless $method;

    my $response;
    if ( $self->can( $method ) ) {
        $response = $self->$method( %{ $args{ $method } || {} } );
    } else {
        $response = $self->http( $method,
            data => $args{ $method } || {},
        );
    }

    if ( blessed $response ) {
        if ( $response->header('content-type') =~ /application\/json/i ) {
            $self->{response} = decode_json( $response->decoded_content );
        } else {
            $self->{response} = $response->decoded_content;
        }
    }

    return undef;
}

sub get_script_method {
    my $data = shift;
    return ( keys %{ $data } )[0];
}

sub get_script {
    my $self = shift;
    my $template = shift;
    my %args = (
        cmd => undef,
        vars => {},
        args => {},
        @_,
    );

    my $cmd = $args{cmd};

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

    my %start_args = $self->start_args;

    my $ret = $template->parse(
        data => $data,
        %args,
        task => $self->{task} || undef,
        vars => {
            tg => sub { $self },
            cmd => $cmd,
            message => $self->message,
            response => sub { $self->{response} },
            callback_query => $self->get_callback_query || {},
            args => $args{args},
            start_args => \%start_args,
            tg_api => sub { $self->tg_api( @_ ) },
        }
    );
    return undef unless $ret;

    # Automatically add a comma between the json objects
    $ret=~s/}{"/},{"/g;

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
        user_login => undef,
        settings => {},
        get_smart_args(@_),
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
        login => $args{user_login} || get_shm_login( $telegram_user_id ),
        password => passgen(),
        full_name => sprintf("%s %s", $tg_user->{first_name}, $tg_user->{last_name} ),
        settings => {
            %{ $args{settings} || {} },
            telegram => {
                user_id => $telegram_user_id,     # field for auth
                username => $tg_user->{username}, # field for manual auth
                login => $tg_user->{username}, # for backward compatible
                first_name => $tg_user->{first_name},
                last_name => $tg_user->{last_name},
                language_code => $tg_user->{language_code},
                is_premium => $tg_user->{is_premium},
                chat_id => $self->chat_id, # for backward compatible
                $self->{profile} => {
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

    if ( $us && $us->delete( force => 1 ) ) {
        return $self->exec_template(
            get_cmd_args( $args{callback_data} ),
        );
    }

    if ( $args{error} ) {
        return $self->sendMessage(
            text => $args{error},
        );
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

    unless ( $args{initData} ) {
        report->error("bad request");
        return undef;
    }

    my %in = CGI->new( $args{initData} )->Vars();
    my $tg_user = decode_json( $in{user} );

    if ( $args{uid} && $self->user->id($args{uid}) ) {
        switch_user( $args{uid} );

        if ( $tg_user->{id} ne $self->user_tg_settings->{user_id} ) {
            report->error("Telegram WebApp auth error: user_id doesn't match");
            return undef;
        }
    } else {
        my ( $user ) = $self->user->_list(
            where => {
                sprintf('%s->>"$.%s"', 'settings', 'telegram.user_id') => $tg_user->{id},
            },
            limit => 1,
        );
        unless ( $user ) {
            logger->error("Telegram WebApp auth error: user not found");
            return undef;
        }

        switch_user( $user->{user_id} );
    }

    $self->profile( $args{profile} );

    my $hash = delete $in{hash};
    my @arr = map( "$_=$in{$_}", sort { $a cmp $b } keys %in );
    my $data_check_string = join("\n", @arr );

    use Digest::SHA qw(hmac_sha256 hmac_sha256_hex);
    my $secret_key = hmac_sha256( $self->token, "WebAppData" );
    my $hex = hmac_sha256_hex( $data_check_string, $secret_key);

    unless ( $hex eq $hash ) {
        report->error('Telegram WebApp auth error');
        return undef;
    }

    return {
        session_id => $self->srv('sessions')->add(),
    };
}

sub web_auth {
    my $self = shift;
    my %args = (
        profile   => 'telegram_bot',
        register_if_not_exists => 0,
        @_,
    );

    my $profile = $args{profile};

    my %in = CGI->new( $args{query} )->Vars();

    my $hash = delete $in{hash};

    my @arr = map { "$_=$in{$_}" } sort keys %in;
    my $data_check_string = join("\n", @arr);

    my $token = $self->config->{ $args{profile} }->{token} // $self->config->{token};
    use Digest::SHA qw(sha256 hmac_sha256_hex);
    my $secret_key = sha256( $token );

    my $hex = hmac_sha256_hex($data_check_string, $secret_key);

    unless ($hex eq $hash) {
        report->error('Telegram WebApp auth error');
        return undef;
    }

    my $chat_id = $in{id};

    my ($user) = $self->user->_list(
        where => {
            -OR => [
                sprintf('%s->>"$.%s"', 'settings', 'telegram.user_id') => $chat_id,
                login => get_shm_login($chat_id),
                sprintf('%s->>"$.%s"', 'settings', 'telegram.chat_id') => $chat_id,
            ],
        },
        limit => 1,
    );

    if ( !$user && $args{register_if_not_exists} ) {
        $user = $self->user->reg(
            login     => sprintf("@%s", $in{id}),
            password  => passgen(),
            full_name => sprintf("%s %s", $in{first_name} || '', $in{last_name} || ''),
            settings  => {
                %{ $args{settings} || {} },
                telegram => {
                    user_id         => $chat_id,
                    username        => $in{username},
                    login           => $in{username},
                    first_name      => $in{first_name} || '',
                    last_name       => $in{last_name} || '',
                    chat_id         => $chat_id,
                    $profile => {
                        chat_id => $chat_id,
                        status  => 'member',
                    },
                },
            },
            $args{partner_id} ? ( partner_id => $args{partner_id} ) : (),
        );
    }

    if ( !$args{register_if_not_exists} && !$user ) {
        logger->error("Telegram WebApp auth error: user not found");
        return undef;
    }

    switch_user( $user->{user_id} );

    return {
        session_id => $self->srv('sessions')->add(),
    };

}

1;
