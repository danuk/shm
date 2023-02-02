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
);

sub init {
    my $self = shift;
    my %args = (
        @_,
    );

    $self->{server} = 'https://api.telegram.org';
    $self->{token} = get_service('config')->data_by_name('telegram')->{token};

    $self->{lwp} = LWP::UserAgent->new(timeout => 5);

    return $self;
}

sub send {
    my $self = shift;
    my $task = shift;

    my %settings = (
        %{ $task->event->{settings} || {} },
    );

    unless ( $self->{token} ) {
        return undef, {
            error => "telegram token not found",
        }
    }

    unless ( $self->chat_id ) {
        return SUCCESS, {
            error => "The user didn't initialize the chat. Skip it.",
        }
    }

    my $message;
    if ( my $template = get_service('template', _id => $settings{template_id} ) ) {
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
    return undef, { error => "message is empty" } unless $message;

    return $self->sendMessage(
        text => $message,
    );
}

sub user {
    return get_service('user');
}

sub chat_id {
    my $self = shift;
    my $chat_id = shift;

    if ( $chat_id ) {
        $self->{chat_id} = $chat_id;
    }

    $self->{chat_id} ||= $self->user->get->{settings}->{telegram}->{chat_id};

    return $self->{chat_id};
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
            document => [ undef, $args{filename}, Content => $data ],
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
            photo => [ undef, $args{filename}, Content => $data ],
        }
    );
}

sub http {
    my $self = shift;
    my $url = shift;
    my %args = (
        method => 'post',
        content_type => 'application/json',
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
        sprintf('%s/bot%s/%s', $self->{server}, $self->{token}, $url ),
        Content_Type => $args{content_type},
        Content => $content,
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
        return FAIL, {
            error => $response->decoded_content,
        };
    }
}

sub sendMessage {
    my $self = shift;
    my %args = (
        text => undef,
        parse_mode => 'Markdown',
        disable_web_page_preview => 'True',
        @_,
    );

    return $self->http( 'sendMessage',
        data => \%args,
    );
}

sub deleteMessage {
    my $self = shift;
    my $id = shift;

    return $self->http(
        'deleteMessage',
        data => {
            message_id => $id,
        },
    );
}

sub sendDocument {
    my $self = shift;
    my %args = (
        document => undef,
        @_,
    );

    return $self->http( 'sendDocument',
        data => \%args,
    );
}

sub sendPhoto {
    my $self = shift;
    my %args = (
        photo => undef,
        @_,
    );

    return $self->http( 'sendPhoto',
        data => \%args,
    );
}

sub auth {
    my $self = shift;
    my $message = shift;

    return undef unless $message->{chat}->{username};

    my ( $user ) = $self->user->_list(
        where => {
            sprintf('%s->"$.%s"', 'settings', 'telegram.login') => $message->{chat}->{username},
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

sub process_message {
    my $self = shift;
    my %args = (
        message => undef,
        @_,
    );

    logger->debug('REQUEST:', \%args );

    my $message = $args{callback_query} ? $args{callback_query}->{message} : $args{message};
    my $message_id = $message->{message_id};

    $self->chat_id( $message->{chat}->{id} );

    my $user = $self->auth( $message );
    unless ( $user ) {
        logger->warning( 'User with login', $message->{chat}->{username}, 'not found' );
        $self->sendMessage(
            text => sprintf("Для работы с Telegram ботом укажите _Telegram логин_ в профиле личного кабинета.\n\n*Telegram логин*: %s\n\n*Кабинет пользователя*: %s ",
                    $message->{chat}->{username},
                    get_service('config')->data_by_name('cli')->{url},
            ),
        );
        return undef;
    }

    my $cmd;
    if ( $args{message} ) {
        $cmd = $args{message}->{text};
    } elsif ( $args{callback_query} ) {
        $cmd = $args{callback_query}->{data};
    }

    $self->deleteMessage( $message_id ) if $cmd !~/^\/(start|show_qr|download_qr)/;

    if ( $cmd eq '/list' ) {
        my @data = $self->user->services->list_for_api;

        my @list;
        for ( @data ) {
            my $icon = $self->get_status_icon( $_->{status} );

            push @list, [{
                text => "$icon $_->{name}",
                callback_data => "/service $_->{user_service_id}",
            }];
        }

        $self->sendMessage(
            text => "🗝 Ключи",
            reply_markup => {
                inline_keyboard => [
                    @list,
                    # [
                    #     {
                    #         text => "🔒 Купить VPN ключ",
                    #         callback_data => "/balance",
                    #     },
                    # ],
                    [
                        {
                            text => "⇦ Назад",
                            callback_data => "/menu",
                        },
                    ],
                ]
            },
        );
    } elsif ( $cmd eq '/balance' ) {
        $self->sendMessage(
            text => sprintf("💰 *Баланс*: %s\n\nНеобходимо оплатить: *%s* ",
                $self->user->get_balance, $self->user->pays->forecast->{total},
            ),
            reply_markup => {
                inline_keyboard => [
                    # [
                    #     {
                    #         text => "✚ Пополнить баланс",
                    #         callback_data => "/payment",
                    #     },
                    # ],
                    [
                        {
                            text => "⇦ Назад",
                            callback_data => "/menu",
                        },
                    ],
                ],
            },
        );
    } elsif ( $cmd =~/^\/service (\d+)/ ) {
        my $usi = $1;
        my ( $us ) =  $self->user->services->list_for_api( usi => $usi );

        $self->sendMessage(
            text => sprintf("*Ключ*: %s\n\n*Оплачен до*: %s\n\n*Статус*: %s (%s) ",
                $us->{name},
                $us->{expire},
                $self->get_status_icon( $us->{status} ),
                $us->{status},
            ),
            reply_markup => {
                inline_keyboard => [
                    [
                        {
                            text => "🗝 Скачать ключ",
                            callback_data => "/download_qr $usi",
                        },
                        {
                            text => "👀 Показать QR код",
                            callback_data => "/show_qr $usi",
                        },
                    ],
                    [
                        {
                            text => "⇦ Назад",
                            callback_data => "/list",
                        },
                    ],
                ],
            },
        );
    } elsif ( $cmd =~/^\/download_qr (\d+)/ ) {
        my $usi = $1;

        if ( my $data = get_service('storage')->list_for_api( name => "vpn$usi" ) ) {
            $self->uploadDocument( $data,
                filename => "vpn$usi.conf",
            );
        } else {
            $self->sendMessage(
                text => "*ОШИБКА*: Ключ не найден",
            );
        }
    } elsif ( $cmd =~/^\/show_qr (\d+)/ ) {
        my $usi = $1;

        if ( my $data = get_service('storage')->list_for_api( name => "vpn$usi" ) ) {
            my $output = qx(echo "$data" | qrencode -t PNG -o -);
            $self->uploadPhoto( $output );
        } else {
            $self->sendMessage(
                text => "*ОШИБКА*: QR код не найден",
            );
        }
    } elsif ( $cmd eq '/pay' ) {
        $self->sendMessage(
            text => "pay",
        );
    } else {
        $self->sendMessage(
            text => "Создавайте и управляйте своими VPN ключами",
            reply_markup => {
                inline_keyboard => [
                    [
                        {
                            text => "💰 Баланс",
                            callback_data => "/balance",
                        },
                    ],
                    [
                        {
                            text => "🗝 Ключи",
                            callback_data => "/list",
                        },
                    ],
                ],
            },
        );
    }

    return 'q';
}

sub get_status_icon {
    my $self = shift;
    my $status = shift;

    my $icon = '⏳';
    $icon = '❌' if $status eq 'BLOCK';
    $icon = '💰' if $status eq 'NOT PAID';
    $icon = '✅' if $status eq 'ACTIVE';

    return $icon;
}

1;
