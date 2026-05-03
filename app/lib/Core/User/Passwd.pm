package Core::User::Passwd;

use v5.14;

use Digest::SHA qw(sha1_hex sha256_hex hmac_sha512);
use Math::Random::Secure qw(rand);

sub passwd {
    my $self = shift;
    my %args = (
        password => undef,
        @_,
    );

    my $report = get_service('report');
    unless ( $args{password} ) {
        $report->add_error('Password is empty');
        return undef;
    }

    my $user = $self;

    if ( $args{admin} && $args{user_id} ) {
        $user = get_service('user', _id => $args{user_id} );
    }

    my $password = $user->make_password( $args{password} );

    get_service('sessions')->delete_user_sessions( user_id => $self->user_id );

    $user->set( password => $password );
    return scalar $user->get;
}

sub set_new_passwd {
    my $self = shift;
    my %args = (
        len => 10,
        admin => 0,
        @_,
    );

    return undef if $self->is_admin && !$args{admin};

    my $new_password = passgen( $args{len} );
    $self->passwd( password => $new_password );

    return $new_password;
}

sub passwd_reset_request {
    my $self = shift;
    my %args = (
        email => undef,
        login => undef,
        @_,
    );

    my $email;
    if ( is_email($args{email}) ) {
       $email = $args{email};
    }

    my $existing_user = $self->check_exists_logins( login => $args{login} || $email );
    my $user_id = $existing_user ? $existing_user->{user_id} : undef;

    if ( !$user_id && $email ) {
        my $profile = get_service("profile");
        my ( $profile_data ) = $profile->_list(
            where => {
                sprintf('%s->>"$.%s"', 'data', 'email') => $email,
            },
            limit => 1,
        );
        $user_id = $profile_data->{user_id} if $profile_data;
    }

    return { msg => 'User not found' } unless $user_id;

    $self = $self->id( $user_id );
    if ( $self->is_blocked ) {
        return { msg => 'User is blocked' };
    }

    unless ( cfg('cli')->{use_for_reset_password} ) {
        $self->make_event( 'user_password_reset' );
        return { msg => 'Successful' };
    }

    my $token = passgen( 35 );
    my $expires = time() + 3600;

    $self->user->set_settings({
        reset_password_verify_token => $token,
        reset_password_verify_expires => $expires,
    });

    my $project_name = cfg('company')->{name} || 'SHM';
    my $url = cfg('cli')->{url};
    my $link = $url ? "$url?token=$token" : undef;
    my %mail_vars = (
        token => $token,
        link => $link || '',
        url => $url || '',
        email => $args{email} || '',
        project_name => $project_name,
    );

    my $subject = $self->render_mail_text(
        text => cfg('mail')->{reset_password}->{subject} || "$project_name - Сброс пароля",
        vars => \%mail_vars,
    );

    my $message = $self->render_mail_text(
        text => cfg('mail')->{reset_password}->{message} || "Ваша ссылка для сброса пароля: {{ link }}\n\nСсылка действительна в течение часа.",
        vars => \%mail_vars,
    );

    $self->send_mail_message(
        to => $args{email},
        subject => $subject,
        message => $message,
    );

    return { msg => 'Successful' };
}

sub is_password_auth_disabled {
    my $self = shift;
    return $self->get_settings->{password_auth_disabled} || 0;
}

sub api_disable_password_auth {
    my $self = shift;

    my $report = get_service('report');

    my $passkey = get_service('User::Passkey');
    unless ($passkey->get_enabled($self)) {
        $report->add_error('PASSKEY_REQUIRED');
        return undef;
    }

    my $settings = $self->get_settings;
    $settings->{password_auth_disabled} = 1;

    delete $settings->{otp};

    $self->set(settings => $settings);

    return {
        success => 1,
        password_auth_disabled => 1,
    };
}

sub api_enable_password_auth {
    my $self = shift;

    my $settings = $self->get_settings;
    delete $settings->{password_auth_disabled};
    $self->set(settings => $settings);

    return {
        success => 1,
        password_auth_disabled => 0,
    };
}

sub api_password_auth_status {
    my $self = shift;

    my $passkey = get_service('User::Passkey');
    my $otp = get_service('User::OTP');

    return {
        password_auth_disabled => $self->is_password_auth_disabled ? 1 : 0,
        passkey_enabled => $passkey->get_enabled($self) ? 1 : 0,
        otp_enabled => $otp->get_enabled($self) ? 1 : 0,
    };
}

sub passwd_reset_verify {
    my $self = shift;
    my %args = (
        token => undef,
        password => undef,
        @_,
    );

    my $token = $args{token};

    my ( $user ) = $self->_list(
        where => {
            sprintf('%s->>"$.%s"', 'settings', 'reset_password_verify_token') => $token,
        },
        limit => 1,
    );

    unless ( $user ) {
        return { msg => 'Invalid token' };
    }

    $self = $self->id( $user->{user_id} );

    my $settings = $self->get_settings;
    unless ( $settings->{reset_password_verify_token} && $settings->{reset_password_verify_token} eq $token ) {
        return { msg => 'Invalid token' };
    }

    if ( $settings->{reset_password_verify_expires} && $settings->{reset_password_verify_expires} < time() ) {
        return { msg => 'Token expired' };
    }

    unless ( $args{password} ) {
        return { msg => 'Successful' };
    }

    delete $settings->{reset_password_verify_token};
    delete $settings->{reset_password_verify_expires};
    $self->set( settings => $settings );

    $self->passwd( password => $args{password} );

    return { msg => 'Password reset successful' };
}

# PBKDF2-HMAC-SHA512 (RFC 2898).
# Args: ($password, $salt_bytes, $iterations, $dklen)
# Returns: $dklen raw bytes of derived key.
sub _pbkdf2 {
    my ( $password, $salt, $iterations, $dklen ) = @_;
    $dklen //= 32;

    my $hlen        = 64;    # SHA-512 output is 64 bytes
    my $block_count = int( ( $dklen + $hlen - 1 ) / $hlen );
    my $dk          = '';

    for my $i ( 1 .. $block_count ) {
        my $u = hmac_sha512( $salt . pack( 'N', $i ), $password );
        my $t = $u;
        for ( 2 .. $iterations ) {
            $u  = hmac_sha512( $u, $password );
            $t ^= $u;
        }
        $dk .= $t;
    }

    return substr( $dk, 0, $dklen );
}

# Create a new password hash using scheme $7$ (PBKDF2-HMAC-SHA512, 100_000 iterations).
# Format: $7$<iterations>$<salt_hex>$<dk_hex>
sub make_password {
    my $self  = shift;
    my $plain = shift;

    my $iterations = 100_000;
    my $salt       = pack( 'C*', map { int( rand(256) ) } 1..16 );
    my $dk         = _pbkdf2( $plain, $salt, $iterations, 32 );

    return sprintf( '$7$%d$%s$%s',
        $iterations, unpack( 'H*', $salt ), unpack( 'H*', $dk ) );
}

# Verify a password against a stored hash.
# Auto-detects scheme by prefix; legacy hashes used the login as salt.
sub verify_password {
    my $self   = shift;
    my $plain  = shift;
    my $stored = shift;
    my $login  = shift;    # needed only for legacy (no-prefix) hashes

    if ( $stored =~ /^\$7\$(\d+)\$([0-9a-f]+)\$([0-9a-f]+)$/ ) {
        # Scheme $7$: PBKDF2-HMAC-SHA512
        my ( $iter, $salt_hex, $expected ) = ( $1 + 0, $2, $3 );
        my $dk = _pbkdf2( $plain, pack( 'H*', $salt_hex ), $iter, 32 );
        return unpack( 'H*', $dk ) eq $expected ? 1 : 0;
    } else {
        # Legacy: sha1(login--password)
        return sha1_hex( join '--', $login, $plain ) eq $stored ? 1 : 0;
    }
}

1;
