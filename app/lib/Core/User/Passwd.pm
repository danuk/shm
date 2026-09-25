package Core::User::Passwd;

use v5.14;

use Core::Base;
use Digest::SHA qw(sha1_hex sha256_hex hmac_sha512);
use Core::Const;
use Core::Utils qw(
    random_bytes
    is_email
    passgen
);

sub passwd {
    my $self = shift;
    my %args = (
        password     => undef,
        old_password => undef,
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

    unless ( $args{admin} ) {
        my $stored = $user->get->{password};

        if ( $stored ) {
            # User has an existing password — must verify it before changing.
            unless ( $args{old_password} ) {
                $report->add_error('OLD_PASSWORD_REQUIRED');
                return undef;
            }
            unless ( $user->verify_password( $args{old_password}, $stored, $user->get_login ) ) {
                $report->add_error('INVALID_OLD_PASSWORD');
                return undef;
            }
        }
        # If the user has no password stored (passkey-only account), allow setting
        # a new password without verification.
    }

    my $password = $user->make_password( $args{password} );

    get_service('sessions')->delete_user_sessions( user_id => $user->user_id );

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

    # Skip the old_password check in passwd(): this is a system-generated
    # reset (e.g. via password-reset email), the caller can't know the old
    # password. Without `admin => 1` passwd() bails out with
    # OLD_PASSWORD_REQUIRED for any account that already has a password,
    # so the new password would be emailed but never actually saved.
    my $ret = $self->passwd( password => $new_password, admin => 1 );
    return undef unless $ret;

    return $new_password;
}

sub send_mail_message {
    my $self = shift;
    my %args = (
        to => undef,
        subject => undef,
        message => undef,
        @_,
    );

    return $self->srv('spool')->add(
        event => {
            title => 'send verify code',
            name => 'SYSTEM',
            server_gid => cfg('mail')->{server_gid} || GROUP_ID_MAIL,
        },
        settings => {
            to => $args{to},
            subject => $args{subject},
            message => $args{message},
            cfg('mail')->{from} ? ( from => cfg('mail')->{from} ) : (),
        },
    );
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
    # Password reset via a mailed link only ever makes sense for login/email
    # identities — never resolve (or later act on) a `phone`-type row here.
    my $existing_user = $self->check_exists_logins( login => $login_str, types => ['login','email'] );
    my $user_id = $existing_user ? $existing_user->{user_id} : undef;

    # Was $email actually confirmed to belong to the resolved account (as
    # opposed to being an arbitrary, unrelated address supplied alongside a
    # different `login`)? Only such a confirmed address may be used as the
    # delivery destination below.
    my $email_confirmed = $user_id && $login_str && lc($login_str) eq lc($email // '') ? 1 : 0;

    if ( !$user_id && $email ) {
        my $profile = get_service("profile");
        my ( $profile_data ) = $profile->_list(
            where => {
                sprintf('%s->>"$.%s"', 'data', 'email') => $email,
            },
            limit => 1,
        );
        if ( $profile_data ) {
            $user_id = $profile_data->{user_id};
            $email_confirmed = 1;
        }
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

    # NOTE: never fall back to $self->get_login (users.login) here — that
    # field is a denormalized copy on the `users` table and is not
    # guaranteed to correspond to any actual row in `accounts`. The account
    # identity for reset purposes is always an `accounts` row of type
    # login/email, already resolved into $login_str above.
    return { msg => 'Login not found' } unless $login_str;

    my $login_obj = $self->logins->id( $login_str, ['login','email'] );
    return { msg => 'Account not found' } unless $login_obj;

    my $token   = passgen( 35 );
    my $expires = time() + 3600;

    $login_obj->set_settings({
        reset_password => {
            token => $token,
            expires => $expires,
        },
    });

    # SECURITY: the reset token must only ever be delivered to an address
    # already tied to the resolved account. Never trust a client-supplied
    # `email` that just happens to be sent alongside a different `login` —
    # otherwise anyone could redirect another user's reset token to an
    # address of their choosing (login=<victim>, email=<attacker>).
    my $send_to = ( $email_confirmed ? $email : undef ) || $self->get_email->{email};
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

    # Must match the same type-scoped lookup used in passwd_reset_request —
    # a `phone` row (or any row found through a different, wider search)
    # could otherwise resolve to a different `accounts` entry than the one
    # the token was actually written to.
    my $login_obj = $self->logins->id( $login_str, ['login','email'] );
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

    # Actually persist the new password. `admin => 1` bypasses the
    # old_password check in passwd() — by design, whoever resets a
    # forgotten password via a mailed token cannot supply the old one.
    my $ret = $self->passwd(
        password => $args{password},
        admin    => 1,
        user_id  => $login_obj->get_user_id,
    );
    return { msg => 'Password reset failed' } unless $ret;

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
