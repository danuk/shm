package Core::Passkey;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( now encode_json decode_json switch_user );

use MIME::Base64 qw(decode_base64url encode_base64url);

sub table { return 'users' };

sub get_settings {
    my $self = shift;
    my $user = shift;
    return $user->get_settings->{passkey} || {};
}

sub set_settings {
    my $self = shift;
    my $user = shift;
    my %passkey_data = @_;

    $user->set_settings({ passkey => \%passkey_data });
}

sub get_credentials {
    my $self = shift;
    my $user = shift;
    my $passkey_settings = $self->get_settings($user);
    return $passkey_settings->{credentials} || [];
}

sub add_credential {
    my $self = shift;
    my $user = shift;
    my %credential = @_;

    my @credentials = @{$self->get_credentials($user)};
    push @credentials, {
        id => $credential{id},
        public_key => $credential{public_key},
        name => $credential{name} || 'Passkey',
        created_at => now(),
        counter => 0,
    };

    $self->set_settings($user, credentials => \@credentials);
}

sub remove_credential {
    my $self = shift;
    my $user = shift;
    my $credential_id = shift;

    my @credentials = @{$self->get_credentials($user)};
    @credentials = grep { $_->{id} ne $credential_id } @credentials;

    if (@credentials) {
        $self->set_settings($user, credentials => \@credentials);
    } else {
        # Если credentials пусто - удаляем весь passkey из settings
        my $settings = $user->get_settings;
        delete $settings->{passkey};
        $user->set(settings => $settings);
    }
}

sub get_enabled {
    my $self = shift;
    my $user = shift;
    my @credentials = @{$self->get_credentials($user)};
    return scalar(@credentials) > 0 ? 1 : 0;
}

sub get_rp_id {
    my $self = shift;

    # Если задан PASSKEY_RP_ID - используем его
    return $ENV{PASSKEY_RP_ID} if $ENV{PASSKEY_RP_ID};

    # Иначе берём HTTP_HOST и убираем порт
    my $host = $ENV{HTTP_HOST} || 'localhost';
    $host =~ s/:\d+$//;  # Убираем порт

    return $host;
}

sub generate_challenge {
    my $self = shift;
    my $user = shift;

    my $challenge = '';
    for (1..32) {
        $challenge .= chr(int(rand(256)));
    }

    my $challenge_b64 = encode_base64url($challenge, '');

    # Сохраняем challenge с временной меткой
    $self->set_settings($user,
        current_challenge => $challenge_b64,
        challenge_created_at => time()
    );

    return $challenge_b64;
}

sub verify_challenge {
    my $self = shift;
    my $user = shift;
    my $client_challenge = shift;

    my $passkey_settings = $self->get_settings($user);
    my $stored_challenge = $passkey_settings->{current_challenge};
    my $challenge_time = $passkey_settings->{challenge_created_at} || 0;

    # Challenge истекает через 5 минут
    return 0 unless $stored_challenge;
    return 0 if (time() - $challenge_time) > 300;
    return 0 unless $client_challenge eq $stored_challenge;

    # Очищаем challenge после использования
    $self->set_settings($user, current_challenge => undef, challenge_created_at => undef);

    return 1;
}

sub api_register_options {
    my $self = shift;

    my $user = get_service('user');
    my $challenge = $self->generate_challenge($user);
    my $project_name = get_service('config')->data_by_name('project')->{name}|| 'SHM';

    # Получаем существующие credential id для исключения
    my @exclude_credentials = map {
        { id => $_->{id}, type => 'public-key' }
    } @{$self->get_credentials($user)};

    return {
        challenge => $challenge,
        rp => {
            name => $project_name,
            id => $self->get_rp_id(),
        },
        user => {
            id => encode_base64url($user->id, ''),
            name => $user->get_login,
            displayName => $user->get_login,
        },
        pubKeyCredParams => [
            { type => 'public-key', alg => -7 },   # ES256
            { type => 'public-key', alg => -257 }, # RS256
        ],
        timeout => 60000,
        attestation => 'none',
        excludeCredentials => \@exclude_credentials,
        authenticatorSelection => {
            authenticatorAttachment => 'platform',
            residentKey => 'preferred',
            userVerification => 'preferred',
        },
    };
}

sub api_register_complete {
    my $self = shift;
    my %args = (
        credential_id => undef,
        rawId => undef,
        response => undef,
        name => undef,
        @_,
    );

    my $report = get_service('report');
    my $user = get_service('user');

    unless ($args{credential_id} && $args{response}) {
        $report->add_error('INVALID_PASSKEY_RESPONSE');
        return undef;
    }

    # Проверяем clientDataJSON
    my $client_data_json = decode_base64url($args{response}->{clientDataJSON} || '');
    my $client_data = decode_json($client_data_json) || {};

    # Проверяем challenge
    unless ($self->verify_challenge($user, $client_data->{challenge})) {
        $report->add_error('INVALID_CHALLENGE');
        return undef;
    }

    # Проверяем тип операции
    unless ($client_data->{type} eq 'webauthn.create') {
        $report->add_error('INVALID_OPERATION_TYPE');
        return undef;
    }

    # Добавляем credential
    $self->add_credential($user,
        id => $args{credential_id},
        public_key => $args{response}->{attestationObject},
        name => $args{name} || 'Passkey ' . (scalar(@{$self->get_credentials($user)}) + 1),
    );

    return {
        success => 1,
        credential_id => $args{credential_id},
    };
}

sub api_auth_options {
    my $self = shift;

    my $user = get_service('user');
    my @credentials = @{$self->get_credentials($user)};

    unless (@credentials) {
        get_service('report')->add_error('NO_PASSKEY_REGISTERED');
        return undef;
    }

    my $challenge = $self->generate_challenge($user);

    my @allow_credentials = map {
        {
            id => $_->{id},
            type => 'public-key',
        }
    } @credentials;

    return {
        challenge => $challenge,
        timeout => 60000,
        rpId => $self->get_rp_id(),
        allowCredentials => \@allow_credentials,
        userVerification => 'preferred',
    };
}

sub api_auth_complete {
    my $self = shift;
    my %args = (
        credential_id => undef,
        rawId => undef,
        response => undef,
        @_,
    );

    my $report = get_service('report');
    my $user = get_service('user');

    unless ($args{credential_id} && $args{response}) {
        $report->add_error('INVALID_PASSKEY_RESPONSE');
        return undef;
    }

    # Проверяем, что credential_id существует
    my @credentials = @{$self->get_credentials($user)};
    my ($credential) = grep { $_->{id} eq $args{credential_id} } @credentials;

    unless ($credential) {
        $report->add_error('UNKNOWN_CREDENTIAL');
        return undef;
    }

    # Проверяем clientDataJSON
    my $client_data_json = decode_base64url($args{response}->{clientDataJSON} || '');
    my $client_data = decode_json($client_data_json) || {};

    # Проверяем challenge
    unless ($self->verify_challenge($user, $client_data->{challenge})) {
        $report->add_error('INVALID_CHALLENGE');
        return undef;
    }

    # Проверяем тип операции
    unless ($client_data->{type} eq 'webauthn.get') {
        $report->add_error('INVALID_OPERATION_TYPE');
        return undef;
    }

    # Обновляем время последней верификации (аналогично OTP)
    $self->set_settings($user, verified_at => now());

    return {
        success => 1,
        session_id => $user->gen_session->{id},
    };
}

sub api_list {
    my $self = shift;

    my $user = get_service('user');
    my @credentials = @{$self->get_credentials($user)};

    # Возвращаем список без приватных данных
    my @safe_list = map {
        {
            id => $_->{id},
            name => $_->{name},
            created_at => $_->{created_at},
        }
    } @credentials;

    return {
        credentials => \@safe_list,
        enabled => $self->get_enabled($user),
    };
}

sub api_delete {
    my $self = shift;
    my %args = (
        credential_id => undef,
        @_,
    );

    my $report = get_service('report');
    my $user = get_service('user');

    unless ($args{credential_id}) {
        $report->add_error('CREDENTIAL_ID_REQUIRED');
        return undef;
    }

    my @credentials = @{$self->get_credentials($user)};
    my ($credential) = grep { $_->{id} eq $args{credential_id} } @credentials;

    unless ($credential) {
        $report->add_error('CREDENTIAL_NOT_FOUND');
        return undef;
    }

    $self->remove_credential($user, $args{credential_id});

    return { success => 1 };
}

sub api_rename {
    my $self = shift;
    my %args = (
        credential_id => undef,
        name => undef,
        @_,
    );

    my $report = get_service('report');
    my $user = get_service('user');

    unless ($args{credential_id} && $args{name}) {
        $report->add_error('CREDENTIAL_ID_AND_NAME_REQUIRED');
        return undef;
    }

    my @credentials = @{$self->get_credentials($user)};
    my $found = 0;

    for my $cred (@credentials) {
        if ($cred->{id} eq $args{credential_id}) {
            $cred->{name} = $args{name};
            $found = 1;
            last;
        }
    }

    unless ($found) {
        $report->add_error('CREDENTIAL_NOT_FOUND');
        return undef;
    }

    $self->set_settings($user, credentials => \@credentials);

    return { success => 1 };
}

sub api_status {
    my $self = shift;

    my $user = get_service('user');
    my $enabled = $self->get_enabled($user);
    my @credentials = @{$self->get_credentials($user)};

    return {
        enabled => $enabled ? 1 : 0,
        credentials_count => scalar(@credentials),
    };
}

# Проверка Passkey при входе (публичный метод)
sub api_auth_options_public {
    my $self = shift;
    my %args = (
        login => undef,
        @_,
    );

    my $report = get_service('report');

    unless ($args{login}) {
        $report->add_error('LOGIN_REQUIRED');
        return undef;
    }

    # Ищем пользователя по логину
    my $user_obj = get_service('user');
    my ($user_row) = $user_obj->_list(
        where => {
            login => lc($args{login}),
        }
    );

    unless ($user_row) {
        $report->add_error('USER_NOT_FOUND');
        return undef;
    }

    my $user = $user_obj->id($user_row->{user_id});

    my @credentials = @{$self->get_credentials($user)};

    unless (@credentials) {
        return {
            passkey_available => 0,
            password_auth_disabled => $user->get_settings->{password_auth_disabled} || 0,
        };
    }

    my $challenge = $self->generate_challenge($user);

    my @allow_credentials = map {
        {
            id => $_->{id},
            type => 'public-key',
        }
    } @credentials;

    return {
        passkey_available => 1,
        challenge => $challenge,
        timeout => 60000,
        rpId => $self->get_rp_id(),
        allowCredentials => \@allow_credentials,
        userVerification => 'preferred',
        password_auth_disabled => $user->get_settings->{password_auth_disabled} || 0,
    };
}

sub api_auth_public {
    my $self = shift;
    my %args = (
        login => undef,
        credential_id => undef,
        rawId => undef,
        response => undef,
        @_,
    );

    my $report = get_service('report');

    unless ($args{login}) {
        $report->add_error('LOGIN_REQUIRED');
        return undef;
    }

    unless ($args{credential_id} && $args{response}) {
        $report->add_error('INVALID_PASSKEY_RESPONSE');
        return undef;
    }

    # Ищем пользователя по логину
    my $user_obj = get_service('user');
    my ($user_row) = $user_obj->_list(
        where => {
            login => lc($args{login}),
        }
    );

    unless ($user_row) {
        $report->add_error('USER_NOT_FOUND');
        return undef;
    }

    my $user = $user_obj->id($user_row->{user_id});

    # Проверяем, что credential_id существует
    my @credentials = @{$self->get_credentials($user)};
    my ($credential) = grep { $_->{id} eq $args{credential_id} } @credentials;

    unless ($credential) {
        $report->add_error('UNKNOWN_CREDENTIAL');
        return undef;
    }

    # Проверяем clientDataJSON
    my $client_data_json = decode_base64url($args{response}->{clientDataJSON} || '');
    my $client_data = decode_json($client_data_json) || {};

    # Проверяем challenge
    unless ($self->verify_challenge($user, $client_data->{challenge})) {
        $report->add_error('INVALID_CHALLENGE');
        return undef;
    }

    # Проверяем тип операции
    unless ($client_data->{type} eq 'webauthn.get') {
        $report->add_error('INVALID_OPERATION_TYPE');
        return undef;
    }

    # Переключаемся на пользователя
    switch_user($user_row->{user_id});

    # Обновляем время последней верификации
    $self->set_settings($user, verified_at => now());

    # Также отмечаем OTP как верифицированный (если включен)
    my $otp = get_service('OTP');
    if ($otp->get_enabled($user)) {
        $otp->set_settings($user, verified_at => now());
    }

    return {
        id => $user->gen_session->{id},
    };
}

1;
