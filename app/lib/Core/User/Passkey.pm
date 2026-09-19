package Core::User::Passkey;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( now encode_json decode_json switch_user );

use MIME::Base64 qw(decode_base64url encode_base64url);
use Digest::SHA qw(sha256);

sub table { return 'users' };

# ---------------------------------------------------------------------------
# Minimal CBOR decoder (RFC 7049) — handles only the subset needed for COSE
# keys embedded in WebAuthn attestationObjects and authData structures.
# ---------------------------------------------------------------------------
sub _cbor_decode {
    my ( $data_ref, $pos_ref ) = @_;

    return undef if $$pos_ref >= length($$data_ref);

    my $first = ord( substr( $$data_ref, $$pos_ref, 1 ) );
    $$pos_ref++;

    my $major = $first >> 5;
    my $info  = $first & 0x1f;

    my $val;
    if    ( $info <= 23 ) { $val = $info; }
    elsif ( $info == 24 ) { $val = ord( substr( $$data_ref, $$pos_ref++, 1 ) ); }
    elsif ( $info == 25 ) { $val = unpack( 'n', substr( $$data_ref, $$pos_ref, 2 ) ); $$pos_ref += 2; }
    elsif ( $info == 26 ) { $val = unpack( 'N', substr( $$data_ref, $$pos_ref, 4 ) ); $$pos_ref += 4; }
    elsif ( $info == 27 ) { $val = unpack( 'Q>', substr( $$data_ref, $$pos_ref, 8 ) ); $$pos_ref += 8; }
    else  { return undef; }    # indefinite-length / reserved — not used by authenticators

    return $val                                   if $major == 0;    # unsigned int
    return ( -1 - $val )                          if $major == 1;    # negative int

    if ( $major == 2 ) {                                             # byte string
        my $s = substr( $$data_ref, $$pos_ref, $val );
        $$pos_ref += $val;
        return $s;
    }
    if ( $major == 3 ) {                                             # text string
        my $s = substr( $$data_ref, $$pos_ref, $val );
        $$pos_ref += $val;
        return $s;
    }
    if ( $major == 4 ) {                                             # array
        my @arr;
        for ( 1 .. $val ) {
            push @arr, _cbor_decode( $data_ref, $pos_ref );
        }
        return \@arr;
    }
    if ( $major == 5 ) {                                             # map
        my %map;
        for ( 1 .. $val ) {
            my $k = _cbor_decode( $data_ref, $pos_ref );
            my $v = _cbor_decode( $data_ref, $pos_ref );
            $map{$k} = $v if defined $k;
        }
        return \%map;
    }
    if ( $major == 6 ) {                                             # tagged item — skip tag
        return _cbor_decode( $data_ref, $pos_ref );
    }
    return undef;
}

# Parse the CBOR attestationObject and extract the COSE public key map.
# Returns a hashref with integer COSE map keys, or undef on failure.
sub _extract_cose_key {
    my ( $self, $attestation_b64 ) = @_;
    return undef unless $attestation_b64;

    my $data = eval { decode_base64url($attestation_b64) };
    return undef unless defined $data && length($data) > 0;

    my $pos = 0;
    my $obj = eval { _cbor_decode( \$data, \$pos ) };
    return undef unless ref($obj) eq 'HASH';

    my $auth_data = $obj->{authData};
    return undef unless defined $auth_data && length($auth_data) > 55;

    my $flags = ord( substr( $auth_data, 32, 1 ) );
    return undef unless $flags & 0x40;    # AT flag: attested credential data present

    my $cred_id_len  = unpack( 'n', substr( $auth_data, 53, 2 ) );
    my $cose_offset  = 55 + $cred_id_len;
    return undef unless length($auth_data) > $cose_offset;

    my $cose_bytes = substr( $auth_data, $cose_offset );
    $pos = 0;
    my $cose = eval { _cbor_decode( \$cose_bytes, \$pos ) };
    return undef unless ref($cose) eq 'HASH';

    return $cose;
}

# Verify a WebAuthn assertion signature.
# Expects base64url-encoded authenticatorData, clientDataJSON, and signature,
# plus the stored COSE key hashref.
sub _verify_assertion_signature {
    my ( $self, %args ) = @_;
    return 0 unless $args{cose_key} && $args{auth_data} && $args{client_json} && $args{signature} && $args{rp_id};

    my $auth_data_bytes  = eval { decode_base64url( $args{auth_data} ) };
    my $client_json_hash = sha256( eval { decode_base64url( $args{client_json} ) } // '' );
    my $sig_bytes        = eval { decode_base64url( $args{signature} ) };

    return 0 unless defined $auth_data_bytes && defined $sig_bytes;
    return 0 unless length($auth_data_bytes) >= 37;

    my $rp_id_hash = substr( $auth_data_bytes, 0, 32 );
    return 0 unless $rp_id_hash eq sha256( $args{rp_id} );

    my $flags = ord( substr( $auth_data_bytes, 32, 1 ) );
    return 0 unless $flags & 0x01;    # user present

    # sigBase = authData || SHA-256(clientDataJSON)  (per WebAuthn §6.3.3)
    my $sig_base = $auth_data_bytes . $client_json_hash;

    my $cose = $args{cose_key};
    my $kty  = $cose->{1};    # 2 = EC2, 3 = RSA
    my $alg  = $cose->{3};    # -7 = ES256, -257 = RS256

    if ( defined $kty && $kty == 2 && defined $alg && $alg == -7 ) {
        # ES256: ECDSA-P256-SHA256
        my $x = $cose->{-2};
        my $y = $cose->{-3};
        return 0 unless defined $x && defined $y;

        my $ok = eval {
            require Crypt::PK::ECC;
            my $pk = Crypt::PK::ECC->new();
            $pk->import_key( {
                kty => 'EC',
                crv => 'P-256',
                x   => encode_base64url( $x, '' ),
                y   => encode_base64url( $y, '' ),
            } );
            $pk->verify_message( $sig_bytes, $sig_base, 'SHA256' );
        };
        return $ok ? 1 : 0;
    }
    elsif ( defined $kty && $kty == 3 && defined $alg && $alg == -257 ) {
        # RS256: RSASSA-PKCS1-v1_5-SHA256
        my $n = $cose->{-1};
        my $e = $cose->{-2};
        return 0 unless defined $n && defined $e;

        my $ok = eval {
            require Crypt::PK::RSA;
            my $pk = Crypt::PK::RSA->new();
            $pk->import_key( {
                kty => 'RSA',
                n   => encode_base64url( $n, '' ),
                e   => encode_base64url( $e, '' ),
            } );
            $pk->verify_message( $sig_bytes, $sig_base, 'SHA256', 'v1.5' );
        };
        return $ok ? 1 : 0;
    }

    return 0;    # unsupported algorithm
}

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
        id         => $credential{id},
        public_key => $credential{public_key},
        cose_key   => $credential{cose_key},
        name       => $credential{name} || 'Passkey ' . ( scalar(@credentials) + 1 ),
        created_at => now(),
        counter    => 0,
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

    my $rp_id = cfg('passkey')->{rp_id};
    return $rp_id if $rp_id;

    return $ENV{PASSKEY_RP_ID} if $ENV{PASSKEY_RP_ID};

    my $host = $ENV{HTTP_X_FORWARDED_HOST} || cfg('cli')->{url} || $ENV{HTTP_HOST} || 'localhost';
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

    my $cose_key = $self->_extract_cose_key( $args{response}->{attestationObject} );
    unless ($cose_key) {
        $report->add_error('INVALID_ATTESTATION_OBJECT');
        return undef;
    }

    $self->add_credential($user,
        id         => $args{credential_id},
        public_key => $args{response}->{attestationObject},
        cose_key   => $cose_key,
        name       => $args{name},
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

    # Verify the cryptographic assertion signature.
    # Falls back to extracting the COSE key from the stored attestationObject
    # for credentials registered before cose_key storage was introduced.
    my $credential = $self->find_credential($user, $args{credential_id});
    my $cose_key   = $credential->{cose_key}
        || $self->_extract_cose_key( $credential->{public_key} );

    unless ($cose_key) {
        $report->add_error('CREDENTIAL_PUBLIC_KEY_UNAVAILABLE');
        return undef;
    }

    unless ( $self->_verify_assertion_signature(
        cose_key    => $cose_key,
        auth_data   => $args{response}->{authenticatorData},
        client_json => $args{response}->{clientDataJSON},
        signature   => $args{response}->{signature},
        rp_id       => $self->get_rp_id(),
    ) ) {
        $report->add_error('INVALID_SIGNATURE');
        return undef;
    }

    switch_user($user_id);
    $self->set_settings($user, verified_at => now());

    # Также отмечаем OTP как верифицированный (если включен)
    my $otp = get_service('User::OTP');
    $otp->set_settings($user, verified_at => now()) if $otp->get_enabled($user);

    return { id => $user->gen_session->{id} };
}

1;
