package Core::User::Passwd;

use v5.14;

use Core::Base;
use Digest::SHA qw(sha1_hex sha256_hex hmac_sha512);
use Core::Utils qw(random_bytes);

sub passwd {
    my $self = shift;
    my %args = (
        password => undef,
        login    => undef,
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

    my $login_str = $args{login} || $user->get_login;
    unless ( $login_str ) {
        $report->add_error('Login not found');
        return undef;
    }

    my $login_obj = $user->logins->id( $login_str );
    unless ( $login_obj ) {
        $report->add_error('Account not found');
        return undef;
    }

    $login_obj->set_password( $args{password} );

    get_service('sessions')->delete_user_sessions( user_id => $user->user_id );

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

    my $login_str = $args{login} || $email;
    my $existing_user = $self->check_exists_logins( login => $login_str );
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


    $login_str ||= $self->get_login;
    return { msg => 'Login not found' } unless $login_str;

    my $login_obj = $self->logins->id( $login_str );
    return { msg => 'Account not found' } unless $login_obj;

    my $token   = passgen( 35 );
    my $expires = time() + 3600;

    $login_obj->set_settings({
        reset_password => {
            token => $token,
            expires => $expires,
        },
    });

    my $send_to = $email || $self->get_email->{email};
    return { msg => 'Email not found' } unless $send_to;

    my $project_name = cfg('company')->{name} || 'SHM';
    my $url = cfg('cli')->{url};
    my $link = $url ? "$url?login=$login_str&token=$token" : undef;
    my %mail_vars = (
        token => $token,
        login => $login_str,
        link => $link || '',
        url => $url || '',
        email => $send_to,
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
        to => $send_to,
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
        login => undef,
        password => undef,
        @_,
    );

    my $token     = $args{token};
    my $login_str = $args{login};

    return { msg => 'Token is required' } unless $token;
    return { msg => 'Login is required' } unless $login_str;

    my $login_obj = $self->logins->id( $login_str );
    return { msg => 'Account not found' } unless $login_obj;

    my $reset = $login_obj->settings->{reset_password} || {};

    unless ( $reset->{token} && $reset->{token} eq $token ) {
        return { msg => 'Invalid token' };
    }

    if ( $reset->{expires} && $reset->{expires} < time() ) {
        return { msg => 'Token expired' };
    }

    unless ( $args{password} ) {
        return { msg => 'Successful' };
    }

    $login_obj->set_settings({
        reset_password => undef,
        email => {
            verified => 1,
        },
    });

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
    my $salt       = random_bytes(16);
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
