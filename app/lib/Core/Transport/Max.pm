package Core::Transport::Max;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;
use Core::System::ServiceManager qw( get_service logger );
use Core::Utils qw(
    switch_user
    encode_json
    decode_json
    decode_base64url
    passgen
    blessed
    now
    parse_headers
    print_header
    print_json
    to_query_string
    uri_escape_utf8
    uri_unescape
);

sub max_server { shift->config->{server} || 'https://platform-api2.max.ru' }

sub http_transport {
    my $self = shift;
    return $self->{http_transport} ||= get_service('Transport::Http');
}

sub config {
    return cfg('max') || {};
}

sub max_settings {
    my $self = shift;
    return $self->config->{ $self->profile_name } || {};
}

sub user_max_settings {
    my $self = shift;

    return $self->{user_max_settings} if $self->{user_max_settings};

    my ( $login ) = $self->user->logins->items_by_types('max');
    return {} unless $login;

    my $data = $self->login->settings->{max} || {};
    my $profile = $data->{ $self->profile_name } || {};

    $data = { %{$data}, %{$profile} };

    return $self->{user_max_settings} = $data || {};
}

sub settings { shift->user_max_settings }
sub username { shift->user_max_settings->{username} }
sub request { shift->{res} }

sub response {
    my $self = shift;
    my $data = shift;
    my $expire = 86400 * 2; # 48h

    if ( $data ) {
        $self->{response} = $data;
        cache->set_json( sprintf('max_response_%s_%s', $self->profile_name, $self->user_id), $data, $expire );
    }

    return $self->{response};
}

sub profile {
    my $self = shift;
    my $name = shift;

    return $self->profile_name unless $name;

    if ( my $profile_name = $self->profile_name ) {
        return $self if
            $profile_name eq $name &&
            $self->{profile} eq $name &&
            $self->{token};
    }

    my $config = $self->config;

    $self->{profile} = $name;
    delete $self->{user_max_settings};  # invalidate per-profile cache

    if ( my $profile = $config->{ $name } ) {
        $self->{token}   = $profile->{token};
        $self->{chat_id} = $profile->{chat_id} if $profile->{chat_id};
    } else {
        $self->{token} = $config->{token};
    }

    $self->{chat_id} ||= $self->user_max_settings->{chat_id};

    return $self;
}

sub profile_name { shift->{profile} }
sub token        { shift->{token}   }
sub chat_id      { shift->{chat_id} }

sub profiles {
    my $self = shift;
    return [ $self->user_profiles() ];
}

sub user_profiles {
    my $self = shift;

    my ( $login ) = $self->user->logins->items_by_types('max');
    my $user_profiles = $login->settings->{max} || {};

    my @profiles;
    for ( keys %$user_profiles ) {
        push @profiles, $_ if ref $user_profiles->{$_} eq 'HASH';
    }

    return wantarray ? @profiles : \@profiles;
}

sub get_message {
    my $self = shift;
    my $res = $self->res || {};
    return undef unless ( $res->{update_type} // '' ) eq 'message_created';
    return $res->{message};
}

sub get_callback {
    my $self = shift;
    my $res = $self->res || {};
    return undef unless ( $res->{update_type} // '' ) eq 'message_callback';
    return $res->{callback};
}

sub max_user {
    my $self = shift;

    if ( my $cb = $self->get_callback ) {
        return $cb->{user};
    }

    my $res = $self->res || {};
    my $update_type = $res->{update_type} // '';

    if ( $update_type eq 'message_created' ) {
        return $res->{message}->{sender};
    } elsif ( $update_type eq 'bot_started' ) {
        return $res->{user};
    } elsif ( $update_type eq 'bot_added' || $update_type eq 'user_added' ) {
        return $res->{user};
    }

    return undef;
}

sub _incoming_chat_id {
    my $self = shift;

    my $res = $self->res || {};
    my $update_type = $res->{update_type} // '';

    if ( $update_type eq 'message_created' ) {
        return $res->{message}->{recipient}->{chat_id};
    } elsif ( $update_type eq 'bot_started' || $update_type eq 'bot_added' ) {
        return $res->{chat_id};
    } elsif ( my $cb = $self->get_callback ) {
        return $cb->{message}->{recipient}->{chat_id};
    }

    return undef;
}

sub message_text {
    my $self = shift;
    if ( my $msg = $self->get_message ) {
        return $msg->{body}->{text} // '';
    }
    if ( my $cb = $self->get_callback ) {
        return $cb->{callback_id} // '';
    }
    return '';
}

sub start_args {
    my $self = shift;
    my %args = ( @_ );

    if ( %args ) {
        $self->{start_args} = \%args;
    }

    return %{ $self->{start_args} || {} };
}

sub cmd {
    my $self = shift;

    my $text = $self->message_text;
    my ( $cmd, @args ) = split /\s+/, $text;

    $cmd //= '';
    $cmd =~ s/^(\/\w+)\s+.*$/$1/;  # strip args from /command

    return $cmd, @args;
}

sub find_user_by_max {
    my $self = shift;
    my $max_user = shift;
    return $self->user->logins->id( $max_user->{user_id}, ['max'] );
}

sub auth {
    my $self = shift;

    my $max_user = $self->max_user;
    return undef unless $max_user;

    my $max_user_id = $max_user->{user_id};
    return undef unless $max_user_id;

    my $login = $self->find_user_by_max( $max_user );
    return undef unless $login;
    return undef unless $self->chat_id;

    switch_user( $login->user_id );

    my %max_settings = (
        max => {
            user_id    => $max_user_id,
            username   => $max_user->{username},
            first_name => $max_user->{name},
            chat_id    => $self->chat_id,
            $self->profile_name() => {
                chat_id => $self->chat_id,
                status  => 'active',
            },
        },
    );

    $login->set_settings({
        auth => {
            date => now(),
        },
        %max_settings,
    });

    return $login->user;
}

# Low-level HTTP call to MAX API.
# MAX uses:  POST /messages?user_id=X  or  POST /messages?chat_id=X
# Auth via:  Authorization: <token> header (NOT query param)
sub http {
    my $self = shift;
    my $method_path = shift;     # e.g. 'messages', 'subscriptions'
    my %args = (
        http_method  => 'post',
        content_type => 'application/json; charset=utf-8',
        data         => {},
        query        => {},
        @_,
    );

    unless ( $self->token ) {
        logger->error('MAX token not defined');
        return {};
    }

    my $http_method = delete $args{http_method};
    my $query       = delete $args{query};

    my $url = sprintf('%s/%s', $self->max_server, $method_path);
    if ( %$query ) {
        $url .= '?' . join('&', map { uri_escape_utf8($_) . '=' . uri_escape_utf8($query->{$_}) } keys %$query);
    }

    my $response = $self->http_transport->http(
        method       => $http_method,
        url          => $url,
        content_type => $args{content_type},
        headers      => {
            Authorization => $self->token,
        },
        content => encode_json( $args{data} ),
    );

    logger->dump('MAX API request',  $response->request );
    logger->dump('MAX API response', $response->decoded_content );

    unless ( $response->is_success ) {
        logger->error( decode_json( $response->decoded_content ) );
    }

    return $response;
}

sub send {
    my $self    = shift;
    my $data    = shift;
    my %settings = (
        format => 'html',
        get_smart_args(@_),
    );

    my @ret;
    my @profiles = $self->profile_name
        ? ( $self->profile_name )
        : $self->user_profiles();

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

        my $response;
        if ( ref $data eq 'HASH' ) {
            # Structured message body — send as-is
            $response = $self->http(
                'messages',
                query => { chat_id => $self->chat_id },
                data  => $data,
            );
        } else {
            $response = $self->sendMessage(
                text   => $data,
                %settings,
            );
        }

        unless ( blessed $response ) {
            push @ret, { error => 'http error', profile => $profile };
            next;
        }

        my $message = decode_json( $response->decoded_content );
        if ( $response->is_success ) {
            logger->info( $message );
            push @ret, { message => 'successful', profile => $profile, response => $message };
            $self->response( $message );
        } else {
            logger->error( $message );
            push @ret, { error => $message, profile => $profile };
        }
    }

    return @ret;
}

sub task_send {
    my $self = shift;
    my $task = shift;

    my %server;
    if ( my $server = $task->server('max') ) {
        %server = $server->get;
    }

    my %settings = (
        %{ $server{settings} || {} },
        %{ $task->event_settings },
        %{ $task->settings },
    );

    my $template = $self->_get_template( $settings{template_id} );
    unless ( $template ) {
        return undef, { error => "template with id `$settings{template_id}` not found" };
    }

    unless ( scalar $self->user_profiles() ) {
        return SUCCESS, { error => "Пользователь не добавил MAX бота" };
    }

    my $message = $template->parse(
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        task => $task,
        vars => {
            max      => sub { $self },
            response => sub { $self->response },
        },
    );

    return SUCCESS, { msg => "Шаблон не содержит данных" } unless $message;

    my @ret = $self->send( $message );

    if ( my $error = $ret[0]->{error} ) {
        return FAIL, $ret[0];
    }

    return SUCCESS, $ret[0];
}

sub _get_template {
    my $self = shift;
    my $id   = shift;

    return undef unless $id;
    return $self->srv('template', _id => $id);
}

sub verify_max_secret {
    my $self = shift;

    if ( my $expected = $self->config->{ $self->profile_name }->{secret} ) {
        my $got = parse_headers->{'x_max_bot_api_secret'};
        return $got eq $expected;
    }
    return 1;
}

sub process_message {
    my $self = shift;
    my %args = (
        profile  => undef,
        template => 'max_bot',
        @_,
    );

    logger->debug('MAX: REQUEST:', \%args);
    $self->res( \%args );

    my $profile_name = $args{profile} || $args{template};
    $self->profile( $profile_name );

    unless ( $self->verify_max_secret ) {
        logger->warning('MAX: webhook secret verification failed');
        return {};
    }

    unless ( $self->token ) {
        logger->error('MAX: token not found for profile', $profile_name);
        return {};
    }

    # Extract chat_id from the incoming update
    if ( my $chat_id = $self->_incoming_chat_id ) {
        $self->{chat_id} = $chat_id;
    }

    my $update_type = $args{update_type} // '';

    # bot_started / bot_added — register or auth user
    if ( $update_type eq 'bot_started' || $update_type eq 'user_added' ) {
        my $user = $self->auth();
        if ( $user ) {
            $user->set_settings({
                max => {
                    $self->profile_name() => { status => 'active' },
                },
            });
        }
        return {};
    }

    # bot_removed — mark user as left
    if ( $update_type eq 'bot_removed' || $update_type eq 'user_removed' ) {
        my $user = $self->auth();
        if ( $user ) {
            $user->set_settings({
                max => {
                    $self->profile_name() => { status => 'left' },
                },
            });
        }
        return {};
    }

    return {} unless $update_type eq 'message_created' || $update_type eq 'message_callback';

    my $user = $self->auth();

    my ( $cmd, @cmd_args ) = $self->cmd;

    if ( $cmd eq '/start' && $cmd_args[0] ) {
        my %start_args;
        for my $pair ( split /&/, decode_base64url( $cmd_args[0] ) ) {
            my ( $key, $value ) = split( /=/, $pair );
            $start_args{ $key } = uri_unescape( $value ) if defined $key && defined $value;
        }
        $self->start_args( %start_args ) if %start_args;
    }

    if ( $cmd ne '/register' ) {
        if ( !$user ) {
            logger->warning( 'MAX: USER_NOT_FOUND:', $self->max_user );
            logger->warning( 'MAX: CMD:', $cmd );
            $cmd = 'USER_NOT_FOUND';
        } elsif ( $user->is_blocked ) {
            $self->sendMessage( text => sprintf("You are blocked! (user_id: %s)", $user->id) );
            return {};
        }
    }

    my $template = $self->_get_template( $args{template} );
    unless ( $template ) {
        logger->warning("MAX: template '$args{template}' not found");
        return {};
    }

    $self->exec_template( cmd => $cmd, template => $template );

    return {};
}

sub sendMessage {
    my $self = shift;
    my %args = (
        text => undef,
        get_smart_args( @_ ),
    );

    $args{text} ||= '__no_text__';

    return $self->http(
        'messages',
        query => { chat_id => $self->chat_id },
        data  => { text => $args{text} },
    );
}

sub shmRegister {
    my $self = shift;
    my %args = (
        callback_data => undef,
        error         => undef,
        partner_id    => undef,
        settings      => {},
        get_smart_args(@_),
    );

    return undef unless $args{callback_data};

    if ( $self->auth ) {
        return $self->exec_template( cmd => $args{callback_data} );
    }

    my $max_user = $self->max_user;
    return undef unless $max_user;

    my %start_args = $self->start_args;
    $args{partner_id} //= $start_args{pid};

    my $max_user_id = $max_user->{user_id};

    my $user = $self->user->reg(
        login      => $max_user_id,
        login_type => 'max',
        full_name  => $max_user->{name} || '',
        settings   => {
            %{ $args{settings} || {} },
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
        }

        my %max_settings = (
            max => {
                user_id    => $max_user_id,
                username   => $max_user->{username},
                first_name => $max_user->{name},
                chat_id    => $self->chat_id,
                $self->profile_name() => {
                    chat_id => $self->chat_id,
                    status  => 'active',
                },
            }
        );
        $user->login->set_settings({
            auth => {
                date => now(),
            },
            %max_settings,
        });

        return $self->exec_template( cmd => $args{callback_data} );
    }

    if ( $args{error} ) {
        return $self->sendMessage( text => $args{error} );
    }

    return {};
}

sub exec_template {
    my $self = shift;
    my %args = (
        cmd      => undef,
        template => undef,
        @_,
    );

    my $template = $args{template} || $self->{_current_template} || return;
    $self->{_current_template} = $template;
    my $cmd = $args{cmd} // '';

    # Phase 1: route — parse template with START/END tags to find the command block
    my $data = $template->parse(
        START_TAG => '<%',
        END_TAG   => '%>',
        vars      => { cmd => $cmd },
    );

    unless ( $data ) {
        logger->warning("MAX: command '$cmd' not found in template", $template->id);
        return;
    }

    # Phase 2: render the selected block
    my $result = $template->parse(
        data => $data,
        vars => {
            max      => sub { $self },
            cmd      => $cmd,
            message  => $self->get_message || {},
            callback => $self->get_callback || {},
            #request => sub { $self->request },
            #response => sub { $self->response },
            #incoming_chat_id => sub { $self->_incoming_chat_id },
        },
    );

    return unless $result;

    # Parse JSON array of API calls
    $result =~ s/}{"/},{"/g;

    my $calls = eval { decode_json("[$result]") };
    return unless $calls && ref $calls eq 'ARRAY';

    for my $call ( @$calls ) {
        next unless ref $call eq 'HASH';

        my ($method) = keys %$call;
        my $call_data = $call->{$method} || {};

        if ( $self->can($method) ) {
            $self->$method( %$call_data );
        } else {
            # Treat as direct MAX API method call
            $self->http(
                $method,
                query => { user_id => $self->chat_id },
                data  => $call_data,
            );
        }
    }
}

sub set_webhook {
    my $self = shift;
    my %args = (
        url          => undef,
        token        => undef,
        secret       => undef,
        template_id  => undef,
        profile      => undef,
        update_types => undef,
        @_,
    );

    $self->{token} = $args{token};

    my $bot_path = $args{template_id};
    $bot_path .= "?profile=$args{profile}" if $args{profile};

    my $webhook_url = sprintf('%s/shm/v1/max/bot/%s', $args{url}, $bot_path);

    my $response = $self->http(
        'subscriptions',
        data => {
            url          => $webhook_url,
            update_types => $args{update_types} // [
                'message_created',
                'message_callback',
                'bot_started',
                'bot_added',
                'bot_removed',
            ],
            $args{secret} ? ( secret => $args{secret} ) : (),
        },
    );

    unless ( blessed $response ) {
        return encode_json({ error => 'http error' });
    }

    logger->dump('MAX set_webhook response', $response->decoded_content);
    return $response->decoded_content;
}

sub api {
    my $self = shift;
    my %args = (
        method => 'post',
        url => 'messages',
        args => {
            chat_id => $self->chat_id,
        },
        data => {
            text => 'Test message',
        },
        get_smart_args( @_ ),
    );

    return $self->http(
        $args{url},
        http_method => $args{method},
        query => $args{args},
        data  => $args{data},
    );
}

1;
