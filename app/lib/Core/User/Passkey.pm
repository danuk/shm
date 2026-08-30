package Core::User::Passkey;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils qw( now encode_json decode_json switch_user );

use MIME::Base64 qw(decode_base64url encode_base64url encode_base64 decode_base64);
use Digest::SHA qw(sha256);
use Crypt::PK::ECC;

sub _cbor_read_uint {
    my ($data, $pos, $info) = @_;
    if ( $info < 24 ) {
        return ( $info, $$pos );
    } elsif ( $info == 24 ) {
        my $v = unpack( 'C', substr( $data, $$pos, 1 ) );
        return ( $v, $$pos + 1 );
    } elsif ( $info == 25 ) {
        my $v = unpack( 'n', substr( $data, $$pos, 2 ) );
        return ( $v, $$pos + 2 );
    } elsif ( $info == 26 ) {
        my $v = unpack( 'N', substr( $data, $$pos, 4 ) );
        return ( $v, $$pos + 4 );
    } elsif ( $info == 27 ) {
        my ( $hi, $lo ) = unpack( 'NN', substr( $data, $$pos, 8 ) );
        return ( $hi * 2**32 + $lo, $$pos + 8 );
    }
    die "CBOR: unsupported additional info $info";
}

sub _cbor_decode_item {
    my ( $data, $pos ) = @_;

    my $first = unpack( 'C', substr( $$data, $$pos, 1 ) );
    $$pos++;
    my $major = $first >> 5;
    my $info  = $first & 0x1f;

    if ( $major == 0 ) { # unsigned int
        my ( $v, $np ) = _cbor_read_uint( $$data, \$$pos, $info );
        $$pos = $np;
        return $v;
    } elsif ( $major == 1 ) { # negative int
        my ( $v, $np ) = _cbor_read_uint( $$data, \$$pos, $info );
        $$pos = $np;
        return -1 - $v;
    } elsif ( $major == 2 ) { # byte string
        my ( $len, $np ) = _cbor_read_uint( $$data, \$$pos, $info );
        $$pos = $np;
        my $v = substr( $$data, $$pos, $len );
        $$pos += $len;
        return $v;
    } elsif ( $major == 3 ) { # text string
        my ( $len, $np ) = _cbor_read_uint( $$data, \$$pos, $info );
        $$pos = $np;
        my $v = substr( $$data, $$pos, $len );
        $$pos += $len;
        return $v;
    } elsif ( $major == 4 ) { # array
        my ( $len, $np ) = _cbor_read_uint( $$data, \$$pos, $info );
        $$pos = $np;
        my @arr;
        push @arr, _cbor_decode_item( $data, $pos ) for 1 .. $len;
        return \@arr;
    } elsif ( $major == 5 ) { # map
        my ( $len, $np ) = _cbor_read_uint( $$data, \$$pos, $info );
        $$pos = $np;
        my %map;
        for ( 1 .. $len ) {
            my $k = _cbor_decode_item( $data, $pos );
            my $v = _cbor_decode_item( $data, $pos );
            $map{ $k } = $v;
        }
        return \%map;
    } elsif ( $major == 7 ) { # simple/float/bool/null
        if ( $info == 20 ) { return 0 }
        if ( $info == 21 ) { return 1 }
        if ( $info == 22 ) { return undef }
        die "CBOR: unsupported simple value $info";
    }
    die "CBOR: unsupported major type $major";
}

sub _cbor_decode {
    my $bytes = shift;
    my $pos = 0;
    return _cbor_decode_item( \$bytes, \$pos );
}

sub _parse_auth_data {
    my $auth_data = shift;

    return undef unless length( $auth_data ) >= 37;

    my $rp_id_hash = substr( $auth_data, 0, 32 );
    my $flags      = unpack( 'C', substr( $auth_data, 32, 1 ) );
    my $counter    = unpack( 'N', substr( $auth_data, 33, 4 ) );

    my %result = (
        rp_id_hash    => $rp_id_hash,
        flags         => $flags,
        user_present  => ( $flags & 0x01 ) ? 1 : 0,
        user_verified => ( $flags & 0x04 ) ? 1 : 0,
        counter       => $counter,
    );

    my $pos = 37;
    if ( $flags & 0x40 && length( $auth_data ) > $pos ) {
        my $aaguid = substr( $auth_data, $pos, 16 ); $pos += 16;
        my $cred_id_len = unpack( 'n', substr( $auth_data, $pos, 2 ) ); $pos += 2;
        my $credential_id = substr( $auth_data, $pos, $cred_id_len ); $pos += $cred_id_len;

        my $cose_key = _cbor_decode_item( \$auth_data, \$pos );

        $result{aaguid} = $aaguid;
        $result{credential_id} = $credential_id;
        $result{cose_key} = $cose_key;
    }

    return \%result;
}

sub _cose_key_to_stored_format {
    my $cose_key = shift;

    return undef unless ref $cose_key eq 'HASH';

    my $kty = $cose_key->{1};
    my $alg = $cose_key->{3};
    my $crv = $cose_key->{-1};
    my $x   = $cose_key->{-2};
    my $y   = $cose_key->{-3};

    return undef unless $kty && $kty == 2 && $crv && $crv == 1 && $x && $y;

    return {
        kty => 2,
        alg => $alg,
        crv => 1,
        x   => unpack( 'H*', $x ),
        y   => unpack( 'H*', $y ),
    };
}

sub _stored_key_to_pk {
    my $stored = shift;

    return undef unless ref $stored eq 'HASH' && $stored->{x} && $stored->{y};

    my $raw = pack( 'C', 0x04 ) . pack( 'H*', $stored->{x} ) . pack( 'H*', $stored->{y} );

    my $pk = eval {
        my $k = Crypt::PK::ECC->new();
        $k->import_key_raw( $raw, 'secp256r1' );
        $k;
    };
    return $pk;
}

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

    my $attestation_object = decode_base64url($args{response}->{attestationObject} || '');
    my $attestation = eval { _cbor_decode($attestation_object) };
    unless ($attestation && ref $attestation eq 'HASH' && $attestation->{authData}) {
        $report->add_error('INVALID_ATTESTATION');
        return undef;
    }

    my $auth_data = eval { _parse_auth_data($attestation->{authData}) };
    unless ($auth_data && $auth_data->{cose_key}) {
        $report->add_error('INVALID_ATTESTATION');
        return undef;
    }

    my $expected_rp_id_hash = sha256($self->get_rp_id());
    unless ($auth_data->{rp_id_hash} eq $expected_rp_id_hash) {
        $report->add_error('RP_ID_MISMATCH');
        return undef;
    }

    my $stored_key = _cose_key_to_stored_format($auth_data->{cose_key});
    unless ($stored_key) {
        $report->add_error('UNSUPPORTED_KEY_ALGORITHM');
        return undef;
    }

    $self->add_credential($user,
        id => $args{credential_id},
        public_key => $stored_key,
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

    my $credential = $self->find_credential($user, $args{credential_id});
    unless ($credential) {
        $report->add_error('UNKNOWN_CREDENTIAL');
        return undef;
    }

    my $pk = _stored_key_to_pk($credential->{public_key});
    unless ($pk) {
        # Легаси/повреждённая запись без корректного публичного ключа - доверять нельзя
        $report->add_error('CREDENTIAL_REQUIRES_REREGISTRATION');
        return undef;
    }

    my $auth_data_raw = decode_base64url($args{response}->{authenticatorData} || '');
    my $signature     = decode_base64url($args{response}->{signature} || '');
    unless ($auth_data_raw && $signature) {
        $report->add_error('INVALID_PASSKEY_RESPONSE');
        return undef;
    }

    my $auth_data = _parse_auth_data($auth_data_raw);
    unless ($auth_data && $auth_data->{user_present}) {
        $report->add_error('INVALID_AUTHENTICATOR_DATA');
        return undef;
    }

    unless ($auth_data->{rp_id_hash} eq sha256($self->get_rp_id())) {
        $report->add_error('RP_ID_MISMATCH');
        return undef;
    }

    my $client_data_json = decode_base64url($args{response}->{clientDataJSON} || '');
    my $signed_data = $auth_data_raw . sha256($client_data_json);

    unless (eval { $pk->verify_message($signature, $signed_data, 'SHA256') }) {
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
