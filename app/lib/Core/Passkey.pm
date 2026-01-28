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
    return $self->get_settings($user)->{credentials} || [];
}

sub find_credential {
    my $self = shift;
    my $user = shift;
    my $credential_id = shift;

    my ($credential) = grep { $_->{id} eq $credential_id } @{$self->get_credentials($user)};
    return $credential;
}

sub add_credential {
    my $self = shift;
    my $user = shift;
    my %credential = @_;

    my @credentials = @{$self->get_credentials($user)};
    push @credentials, {
        id => $credential{id},
        public_key => $credential{public_key},
        name => $credential{name} || 'Passkey ' . (scalar(@credentials) + 1),
        created_at => now(),
        counter => 0,
    };

    $self->set_settings($user, credentials => \@credentials);
}

sub remove_credential {
    my $self = shift;
    my $user = shift;
    my $credential_id = shift;

    my @credentials = grep { $_->{id} ne $credential_id } @{$self->get_credentials($user)};

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
    return scalar(@{$self->get_credentials($user)}) > 0 ? 1 : 0;
}

sub get_rp_id {
    my $self = shift;

    return $ENV{PASSKEY_RP_ID} if $ENV{PASSKEY_RP_ID};

    my $host = $ENV{HTTP_HOST} || 'localhost';
    $host =~ s/:\d+$//;
    return $host;
}

sub generate_challenge {
    my $self = shift;
    my $user_id = shift;

    my $challenge = join('', map { chr(int(rand(256))) } 1..32);
    my $challenge_b64 = encode_base64url($challenge, '');

    my $cache = get_service('Core::System::Cache');
    $cache->set("passkey_challenge:$challenge_b64", $user_id || 0, 300);

    return $challenge_b64;
}

sub verify_challenge {
    my $self = shift;
    my $challenge = shift;
    my $expected_user_id = shift;

    return 0 unless $challenge;

    my $cache = get_service('Core::System::Cache');
    my $key = "passkey_challenge:$challenge";

    my $stored_value = $cache->get($key);
    return 0 unless defined $stored_value;

    if ($expected_user_id && $stored_value) {
        return 0 unless $stored_value eq $expected_user_id;
    }

    $cache->delete($key);

    return 1;
}

sub parse_client_data {
    my $self = shift;
    my $client_data_b64 = shift;
    my $expected_type = shift;

    my $client_data_json = decode_base64url($client_data_b64 || '');
    my $client_data = decode_json($client_data_json) || {};

    return undef unless $client_data->{type} eq $expected_type;
    return $client_data;
}

sub api_register_options {
    my $self = shift;

    my $user = get_service('user');
    my $challenge = $self->generate_challenge($user->id);
    my $project_name = get_service('config')->data_by_name('project')->{name} || 'SHM';

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
        excludeCredentials => [
            map { { id => $_->{id}, type => 'public-key' } } @{$self->get_credentials($user)}
        ],
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

    my $client_data = $self->parse_client_data($args{response}->{clientDataJSON}, 'webauthn.create');
    unless ($client_data) {
        $report->add_error('INVALID_OPERATION_TYPE');
        return undef;
    }

    unless ($self->verify_challenge($client_data->{challenge}, $user->id)) {
        $report->add_error('INVALID_CHALLENGE');
        return undef;
    }

    $self->add_credential($user,
        id => $args{credential_id},
        public_key => $args{response}->{attestationObject},
        name => $args{name},
    );

    return {
        success => 1,
        credential_id => $args{credential_id},
    };
}

sub api_list {
    my $self = shift;

    my $user = get_service('user');

    return {
        credentials => [
            map { { id => $_->{id}, name => $_->{name}, created_at => $_->{created_at} } }
            @{$self->get_credentials($user)}
        ],
        enabled => $self->get_enabled($user),
    };
}

sub api_delete {
    my $self = shift;
    my %args = ( credential_id => undef, @_ );

    my $report = get_service('report');
    my $user = get_service('user');

    unless ($args{credential_id}) {
        $report->add_error('CREDENTIAL_ID_REQUIRED');
        return undef;
    }

    unless ($self->find_credential($user, $args{credential_id})) {
        $report->add_error('CREDENTIAL_NOT_FOUND');
        return undef;
    }

    $self->remove_credential($user, $args{credential_id});
    return { success => 1 };
}

sub api_rename {
    my $self = shift;
    my %args = ( credential_id => undef, name => undef, @_ );

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

    return {
        enabled => $self->get_enabled($user),
        credentials_count => scalar(@{$self->get_credentials($user)}),
    };
}

# Публичный метод аутентификации (без логина)
sub api_auth_options_public {
    my $self = shift;

    return {
        challenge => $self->generate_challenge(),
        timeout => 60000,
        rpId => $self->get_rp_id(),
        userVerification => 'preferred',
    };
}

sub api_auth_public {
    my $self = shift;
    my %args = ( credential_id => undef, response => undef, @_ );

    my $report = get_service('report');

    unless ($args{credential_id} && $args{response}) {
        $report->add_error('INVALID_PASSKEY_RESPONSE');
        return undef;
    }

    # Получаем userHandle из ответа (это user_id в base64url)
    my $user_handle = $args{response}->{userHandle};
    unless ($user_handle) {
        $report->add_error('USER_HANDLE_REQUIRED');
        return undef;
    }

    # Декодируем user_id из userHandle
    my $user_id = decode_base64url($user_handle);
    unless ($user_id && $user_id =~ /^\d+$/) {
        $report->add_error('INVALID_USER_HANDLE');
        return undef;
    }

    my $client_data = $self->parse_client_data($args{response}->{clientDataJSON}, 'webauthn.get');
    unless ($client_data) {
        $report->add_error('INVALID_OPERATION_TYPE');
        return undef;
    }

    unless ($self->verify_challenge($client_data->{challenge})) {
        $report->add_error('INVALID_CHALLENGE');
        return undef;
    }

    # Ищем пользователя по user_id
    my $user = get_service('user')->id($user_id);
    unless ($user->get) {
        $report->add_error('USER_NOT_FOUND');
        return undef;
    }

    unless ($self->find_credential($user, $args{credential_id})) {
        $report->add_error('UNKNOWN_CREDENTIAL');
        return undef;
    }

    switch_user($user_id);
    $self->set_settings($user, verified_at => now());

    # Также отмечаем OTP как верифицированный (если включен)
    my $otp = get_service('OTP');
    $otp->set_settings($user, verified_at => now()) if $otp->get_enabled($user);

    return { id => $user->gen_session->{id} };
}

1;
