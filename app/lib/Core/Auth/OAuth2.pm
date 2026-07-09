package Core::Auth::OAuth2;

use v5.14;
use parent 'Core::Auth::Base', 'Core::Auth::OAuth2::Google', 'Core::Auth::OAuth2::Yandex', 'Core::Auth::OAuth2::GitHub';
use Core::Base;
use SHM qw( validate_session );
use Core::System::ServiceManager qw( get_service logger );
use Core::Utils qw(
    switch_user
    encode_json
    decode_json
    encode_base64url
    decode_base64url
    random_base64url
    jwt_decode
    passgen
    sha256
    print_header
    print_json
    hash_merge
);
use URI::Escape qw( uri_escape );

sub oauth2_config {
    my $self = shift;
    my $provider = shift;
    my $cfg = cfg('oauth2') || {};
    return $cfg->{$provider} || {};
}

sub require_enabled_provider {
    my $self = shift;
    my $provider = shift;

    my $pcfg = $self->provider_config( $provider );
    unless ( $pcfg ) {
        report->status( 400 );
        report->error("Unknown OAuth2 provider: " . ( $provider // '' ));
        return 0;
    }

    unless ( $self->oauth2_config( $provider )->{enabled} ) {
        report->status( 403 );
        report->error("OAuth2 provider is disabled: $provider");
        return 0;
    }

    return 1;
}

sub client_id {
    my $self = shift;
    my $provider = shift;
    return $self->oauth2_config( $provider )->{client_id};
}

sub client_secret {
    my $self = shift;
    my $provider = shift;
    return $self->oauth2_config( $provider )->{client_secret};
}

sub oauth2_callback_url {
    my $self = shift;
    my $provider = shift;
    return $self->callback_url( $provider, 'oauth2' );
}

sub oauth2_state_cache_key {
    my $self = shift;
    my $state = shift;
    return $self->auth_state_cache_key( $state, 'oauth2_state' );
}

sub oauth2_init {
    my $self = shift;
    my %args = (
        provider => undef,
        redirect_uri => undef,
        return_url => undef,
        bind_to_profile => 0,
        bind_only_if_new => 0,
        session_id => undef,
        ttl => 600,
        @_,
    );

    my $provider = $args{provider};
    return undef unless $self->require_enabled_provider( $provider );
    my $pcfg = $self->provider_config( $provider );

    my $client_id = $self->client_id( $provider );
    unless ( $client_id ) {
        report->status( 400 );
        report->error("OAuth2 client_id is not configured for provider: $provider");
        return undef;
    }

    my $redirect_uri = $args{redirect_uri} || $self->oauth2_callback_url( $provider );

    my $state = random_base64url(32);
    my $nonce = random_base64url(32);
    my $code_verifier = random_base64url(32);
    my $code_challenge = encode_base64url( sha256($code_verifier) );
    my $device_id = random_base64url(16);

    my $ctx = {
        state => $state,
        nonce => $nonce,
        code_verifier => $code_verifier,
        device_id => $device_id,
        provider => $provider,
        redirect_uri => $redirect_uri,
        ( defined $args{return_url} ? ( return_url => $args{return_url} ) : () ),
        bind_to_profile => $args{bind_to_profile} ? 1 : 0,
        bind_only_if_new => $args{bind_only_if_new} ? 1 : 0,
        ( defined $args{session_id} ? ( session_id => $args{session_id} ) : () ),
    };

    cache->set_json( $self->oauth2_state_cache_key($state), $ctx, $args{ttl} );

    my $scope = $self->provider_scope( $provider );
    my $auth_url = sprintf(
        '%s?client_id=%s&redirect_uri=%s&response_type=code&scope=%s&state=%s&nonce=%s&code_challenge=%s&code_challenge_method=S256',
        $pcfg->{authorize_endpoint},
        uri_escape($client_id),
        uri_escape($redirect_uri),
        uri_escape($scope),
        uri_escape($state),
        uri_escape($nonce),
        uri_escape($code_challenge),
    );
    $auth_url .= '&device_id=' . uri_escape($device_id) if $pcfg->{requires_device_id};

    return {
        auth_url => $auth_url,
        state => $state,
        nonce => $nonce,
        code_challenge => $code_challenge,
        code_challenge_method => 'S256',
        redirect_uri => $redirect_uri,
        expires_in => int($args{ttl}),
    };
}

sub oauth2_start_redirect {
    my $self = shift;
    my %args = @_;

    my $payload = $self->oauth2_init(%args);
    return undef unless $payload;

    my $auth_url = $payload->{auth_url};
    unless ( $auth_url ) {
        report->error('OAuth2 auth_url is empty');
        return undef;
    }

    if ( $ENV{SHM_TEST} ) {
        return {
            status => 302,
            redirect => $auth_url,
            %{$payload},
        };
    }

    print_header(status => 302, Location => $auth_url);
    print_json({ status => 302, redirect => $auth_url });
    exit 0;
}

sub oauth2_exchange_code {
    my $self = shift;
    my %args = (
        provider => undef,
        code => undef,
        redirect_uri => undef,
        code_verifier => undef,
        device_id => undef,
        @_,
    );

    my $provider = $args{provider};
    my $pcfg = $self->provider_config( $provider ) || return undef;

    for my $required ( qw(code redirect_uri) ) {
        unless ( defined $args{$required} && $args{$required} ne '' ) {
            report->error("OAuth2 $required is required");
            return undef;
        }
    }

    my $client_id = $self->client_id( $provider );
    my $client_secret = $self->client_secret( $provider );
    unless ( $client_id && $client_secret ) {
        report->error("OAuth2 client_id/client_secret is not configured for provider: $provider");
        return undef;
    }

    my %form = (
        grant_type => 'authorization_code',
        code => $args{code},
        redirect_uri => $args{redirect_uri},
        client_id => $client_id,
        client_secret => $client_secret,
    );
    $form{code_verifier} = $args{code_verifier} if defined $args{code_verifier} && $args{code_verifier} ne '';
    if ( $pcfg->{requires_device_id} ) {
        unless ( defined $args{device_id} && $args{device_id} ne '' ) {
            report->error("OAuth2 device_id is required ($provider)");
            return undef;
        }
        $form{device_id} = $args{device_id};
    }

    my $content = join '&', map {
        uri_escape($_) . '=' . uri_escape( defined $form{$_} ? $form{$_} : '' )
    } sort keys %form;

    my $response = $self->http_transport->http(
        method => 'post',
        url => $pcfg->{token_endpoint},
        content_type => 'application/x-www-form-urlencoded',
        headers => { Accept => 'application/json' },
        content => $content,
    );

    my $body = $response->decoded_content;
    my $json = eval { decode_json($body) };

    my $has_error = ( ref $json eq 'HASH' && $json->{error} );
    if ( !$response->is_success || $has_error ) {
        my $error = ref $json eq 'HASH' ? ( $json->{error_description} || $json->{error} || $body ) : $body;
        report->error("OAuth2 token exchange failed ($provider): $error");
        return undef;
    }

    unless ( ref $json eq 'HASH' && ( $json->{access_token} || $json->{id_token} ) ) {
        report->error("OAuth2 token response is invalid ($provider)");
        return undef;
    }

    return $json;
}

sub oauth2_jwks {
    my $self = shift;
    my $provider = shift;
    my $pcfg = $self->provider_config( $provider ) || return [];

    state %cache_by_provider;
    my $c = $cache_by_provider{$provider} ||= { fetched_at => 0, keys => [] };

    my $ttl = 3600;
    if ( time - $c->{fetched_at} < $ttl && ref $c->{keys} eq 'ARRAY' && @{ $c->{keys} } ) {
        return $c->{keys};
    }

    my $response = $self->http_transport->http(
        method => 'get',
        url => $pcfg->{jwks_uri},
    );
    unless ( $response->is_success ) {
        report->error("OAuth2 jwks request failed ($provider)");
        return [];
    }

    my $json = decode_json( $response->decoded_content ) || {};
    my $keys = $json->{keys};
    unless ( ref $keys eq 'ARRAY' && @$keys ) {
        report->error("OAuth2 jwks response is invalid ($provider)");
        return [];
    }

    $c->{fetched_at} = time;
    $c->{keys} = $keys;

    return $c->{keys};
}

sub oauth2_verify_id_token {
    my $self = shift;
    my %args = (
        provider => undef,
        id_token => undef,
        nonce => undef,
        @_,
    );

    my $provider = $args{provider};
    my $pcfg = $self->provider_config( $provider ) || return undef;
    my $id_token = $args{id_token};
    return undef unless $id_token;

    my ($header_b64) = split /\./, $id_token;
    my $header = decode_json( decode_base64url( $header_b64 ) ) || {};
    my $kid = $header->{kid};

    my $client_id = $self->client_id( $provider );
    unless ( $client_id ) {
        report->error("OAuth2 client_id is not configured for provider: $provider");
        return undef;
    }

    my $jwks = $self->oauth2_jwks( $provider );
    my @keys = grep { ref $_ eq 'HASH' && ( !$kid || ( $_->{kid} || '' ) eq $kid ) } @{ $jwks || [] };
    @keys = @{ $jwks || [] } unless @keys;

    my $claims;
    for my $jwk ( @keys ) {
        next unless ref $jwk eq 'HASH';

        my $decoded;
        my $ok = eval {
            $decoded = jwt_decode(
                token => $id_token,
                key => $jwk,
                accepted_alg => ['RS256'],
                verify_exp => 0,
                verify_iat => 0,
                verify_nbf => 0,
            );
            1;
        };

        if ( $ok ) {
            $claims = $decoded;
            last;
        }
    }

    unless ( ref $claims eq 'HASH' ) {
        report->error("OAuth2 id_token signature verification failed ($provider)");
        return undef;
    }

    unless ( ( $claims->{iss} || '' ) eq $pcfg->{issuer} ) {
        report->error("OAuth2 id_token has invalid iss ($provider)");
        return undef;
    }

    my $aud = $claims->{aud};
    my $aud_ok = ref $aud eq 'ARRAY'
        ? scalar( grep { defined $_ && "$_" eq "$client_id" } @$aud )
        : ( defined $aud && "$aud" eq "$client_id" );
    unless ( $aud_ok ) {
        report->error("OAuth2 id_token has invalid aud ($provider)");
        return undef;
    }

    my $now = time;
    if ( !$claims->{exp} || $claims->{exp} < $now ) {
        report->error("OAuth2 id_token is expired ($provider)");
        return undef;
    }
    if ( $claims->{iat} && $claims->{iat} > $now + 60 ) {
        report->error("OAuth2 id_token has invalid iat ($provider)");
        return undef;
    }
    if ( defined $args{nonce} && $args{nonce} ne '' ) {
        unless ( defined $claims->{nonce} && $claims->{nonce} eq $args{nonce} ) {
            report->error("OAuth2 id_token has invalid nonce ($provider)");
            return undef;
        }
    }

    return $claims;
}

sub oauth2_fetch_userinfo {
    my $self = shift;
    my %args = (
        provider => undef,
        access_token => undef,
        @_,
    );

    my $provider = $args{provider};
    my $pcfg = $self->provider_config( $provider ) || return undef;
    return undef unless $args{access_token};

    my $response;
    if ( ( $pcfg->{userinfo_auth} || '' ) eq 'client_params' ) {
        my $client_id = $self->client_id( $provider );
        my $content = join '&',
            'client_id=' . uri_escape($client_id||''),
            'access_token=' . uri_escape($args{access_token});
        $response = $self->http_transport->http(
            method => 'post',
            url => $pcfg->{userinfo_endpoint},
            content_type => 'application/x-www-form-urlencoded',
            content => $content,
        );
    } elsif ( ( $pcfg->{userinfo_auth} || '' ) eq 'bearer' ) {
        $response = $self->http_transport->http(
            method => 'get',
            url => $pcfg->{userinfo_endpoint},
            headers => {
                Authorization => "Bearer $args{access_token}",
                Accept => 'application/json',
                ( $pcfg->{user_agent} ? ( 'User-Agent' => $pcfg->{user_agent} ) : () ),
            },
        );
    } else {
        $response = $self->http_transport->http(
            method => 'get',
            url => $pcfg->{userinfo_endpoint} . '?format=json',
            headers => { Authorization => "OAuth $args{access_token}" },
        );
    }

    my $json = eval { decode_json( $response->decoded_content ) };

    if ( !$response->is_success || ( ref $json eq 'HASH' && $json->{error} ) ) {
        my $error = ref $json eq 'HASH' ? ( $json->{error_description} || $json->{error} || '' ) : '';
        report->error("OAuth2 userinfo request failed ($provider): $error");
        return undef;
    }

    unless ( ref $json eq 'HASH' ) {
        report->error("OAuth2 userinfo response is invalid ($provider)");
        return undef;
    }

    if ( !$json->{email} && $pcfg->{emails_endpoint} ) {
        my $emails_response = $self->http_transport->http(
            method => 'get',
            url => $pcfg->{emails_endpoint},
            headers => {
                Authorization => "Bearer $args{access_token}",
                Accept => 'application/json',
                ( $pcfg->{user_agent} ? ( 'User-Agent' => $pcfg->{user_agent} ) : () ),
            },
        );
        my $emails = eval { decode_json( $emails_response->decoded_content ) };
        $json->{__emails} = $emails if ref $emails eq 'ARRAY';
    }

    return $json;
}

sub oauth2_callback {
    my $self = shift;
    my %args = (
        provider => undef,
        bind_to_profile => 0,
        bind_only_if_new => 0,
        session_id => undef,
        device_id => undef,
        @_,
    );

    my $provider = $args{provider};
    return undef unless $self->require_enabled_provider( $provider );
    my $pcfg = $self->provider_config( $provider );

    my $uid;
    if ( $args{bind_to_profile} ) {
        my $session = validate_session( session_id => $args{session_id} );
        unless ( $session ) {
            report->status( 401 );
            report->error('A valid session is required to bind an account');
            return undef;
        }
        $uid = $session->user_id;
    }

    if ( $args{expected_state} && defined $args{state} && $args{state} ne $args{expected_state} ) {
        report->error('OAuth2 state mismatch');
        $self->set_user_fail_attempt( 'oauth2_callback', 3600 );
        return undef;
    }

    my $claims_raw;
    my $access_token;

    if ( $args{code} ) {
        my $tokens = $self->oauth2_exchange_code(
            provider => $provider,
            code => $args{code},
            redirect_uri => $args{redirect_uri},
            code_verifier => $args{code_verifier},
            device_id => $args{device_id},
        );
        return undef unless $tokens;

        $access_token = $tokens->{access_token};

        if ( $pcfg->{verify_mode} eq 'id_token' ) {
            return undef unless $tokens->{id_token};
            $claims_raw = $self->oauth2_verify_id_token(
                provider => $provider,
                id_token => $tokens->{id_token},
                nonce => $args{nonce},
            );
            return undef unless $claims_raw;
        } else {
            return undef unless $access_token;
            $claims_raw = $self->oauth2_fetch_userinfo(
                provider => $provider,
                access_token => $access_token,
            );
            return undef unless $claims_raw;
        }
    } else {
        report->error('OAuth2 code is required');
        return undef;
    }

    my $claims = $self->normalize_claims( $provider, $claims_raw );
    my $email = $claims->{email}{address};
    unless ( $email ) {
        report->error("OAuth2 claims have no email ($provider)");
        return undef;
    }

    if ( $uid && $self->user->id($uid) ) {
        switch_user( $uid );

        my $existing = $self->user->logins->id( $email, ['email', 'login'] );
        if ( $existing && $existing->get_user_id ne $uid ) {
            return { error => 'Email already linked to another user' };
        }
        my $existing_provider = $self->user->logins->id( $email, [$self->oauth2_login_type($provider)] );
        my $already_bound = $existing_provider && $self->oauth2_account_is_linked( $existing_provider->get_settings || {} );

        $self->save_oauth2_account( $self->user, $provider, $claims );
        return { error => "Already bound to $provider" } if $already_bound;
        return { msg => "Successfully bound to $provider" };
    }

    my $login_obj = $self->user->logins->id( $email, ['email', 'login'] );
    my $provider_login_obj = $self->user->logins->id( $email, [$self->oauth2_login_type($provider)] );

    my $user;
    if ( $login_obj ) {
        my $settings = $provider_login_obj ? ( $provider_login_obj->get_settings || {} ) : {};
        unless ( $self->oauth2_account_is_linked( $settings ) ) {
            return { error => "Account with this email exists but is not linked to $provider yet. Log in and link your $provider account from your profile first." };
        }
        $user = $self->user->id( $login_obj->get_user_id );
        $self->save_oauth2_account( $user, $provider, $claims );
    } else {
        $user = $self->user->reg(
            login => $email,
            login_type => 'email',
            password => passgen(),
            full_name => $claims->{name} || '',
        );
        if ( $user && $claims->{email}{verified} ) {
            my $email_login = $user->logins->id( $email, ['email'] );
            $email_login->set_settings( hash_merge( $email_login->get_settings || {}, { email => { verified => 1 } } ) ) if $email_login;
        }
        $self->save_oauth2_account( $user, $provider, $claims ) if $user;
    }

    unless ( $user ) {
        logger->error("OAuth2 auth error ($provider): user not found");
        return undef;
    }

    return {
        session_id => $user->srv('sessions')->add(),
    };
}

sub oauth2_login_type {
    my $self = shift;
    my $provider = shift;
    return "${provider}_oauth2";
}

sub oauth2_account_is_linked {
    my $self = shift;
    my $settings = shift || {};
    return 1 if ref($settings) eq 'HASH' && $settings->{email};
    return 0;
}

sub save_oauth2_account {
    my $self = shift;
    my $user = shift;
    my $provider = shift;
    my $claims = shift;
    my $email = $claims->{email}{address};
    return unless $user && $email;

    my $login_obj = $user->logins->id( $email, [$self->oauth2_login_type($provider)] );

    if ( $login_obj ) {
        $login_obj->set_settings( hash_merge( $login_obj->get_settings || {}, $claims ) );
    } else {
        $user->logins->add( login => $email, type => $self->oauth2_login_type($provider), settings => $claims );
    }
}

sub oauth2_callback_redirect {
    my $self = shift;
    my %args = (
        provider => undef,
        bind_to_profile => 0,
        bind_only_if_new => 0,
        @_,
    );

    %args = %{ $self->resolve_callback_state( \%args, 'oauth2_state' ) };
    $args{redirect_uri} ||= $self->oauth2_callback_url( $args{provider} );

    my $result = $self->oauth2_callback( %args );

    my $return_url = $args{return_url};
    return $result unless $return_url;

    my $redirect_url = $self->build_callback_redirect_url(
        $result,
        $return_url,
        'OAuth2 authentication failed',
        'oauth2_status',
    );

    if ( $ENV{SHM_TEST} ) {
        return { status => 302, redirect => $redirect_url };
    }

    print_header( status => 302, Location => $redirect_url );
    print_json({ status => 302, redirect => $redirect_url });
    exit 0;
}

1;
