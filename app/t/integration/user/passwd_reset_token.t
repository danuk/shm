use v5.14;
use utf8;

use Test::More;
use Test::Deep;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;

my $admin = SHM->new( user_id => 40092 );

# --- enable the token-based reset flow (cfg('cli')->{use_for_reset_password}) ---
# The `cli` config key does not exist by default, so create/patch it and
# restore the original state afterwards to avoid affecting other tests.
my $config       = get_service('config');
my $cli_obj      = $config->id('cli');
my $cli_existed  = defined $cli_obj;
my %orig_cli     = $cli_existed ? %{ $cli_obj->get_data || {} } : ();

if ( $cli_existed ) {
    $cli_obj->set( value => { %orig_cli, use_for_reset_password => 1, url => 'https://cabinet.example.com' } );
} else {
    $config->add( key => 'cli', value => { use_for_reset_password => 1, url => 'https://cabinet.example.com' } );
}

END {
    my $config = get_service('config');
    my $cli    = $config->id('cli');
    if ( $cli ) {
        if ( $cli_existed ) {
            $cli->set( value => \%orig_cli );
        } else {
            $cli->delete();
        }
    }
}

my $email        = sprintf( 'passwd_reset_token_%d@domain.ru', time() );
my $old_password = 'initial_password_123';
my $new_password  = 'brand_new_password_456';

my $user = $admin->reg(
    login    => $email,
    login_type => 'email',
    password => $old_password,
);
ok( $user, 'Test user registered' ) or done_testing(), exit;

subtest 'Request password reset creates a token tied to the email login' => sub {
    my $ret = $user->passwd_reset_request( email => $email );
    is( $ret->{msg}, 'Successful', 'Reset request accepted' );

    my $login_obj = $user->logins->id( $email, ['email'] );
    ok( $login_obj, 'Email login exists' );

    my $reset = $login_obj->settings->{reset_password} || {};
    ok( $reset->{token}, 'Token was generated' );
    ok( $reset->{expires} && $reset->{expires} > time(), 'Token expiry is in the future' );

    # The mailed link must contain both the email/login and the token.
    # NOTE: list() auto-scopes to the *service instance's own* user_id
    # (Spool.user_id is auto_fill), so it must be fetched via a spool
    # instance bound to this user, same as send_mail_message() does
    # internally through $self->srv('spool').
    my $spool = $user->srv('spool');
    my @rows  = $spool->list;
    my ( $row ) = sort { $b->{id} <=> $a->{id} } @rows;
    ok( $row, 'A reset e-mail was queued' );

    my $message = $row->{settings}->{message} || '';
    like( $message, qr/\Q$email\E/, 'Message/link contains the email' );
    like( $message, qr/\Q$reset->{token}\E/, 'Message/link contains the token' );

    $spool->id( $row->{id} )->delete();
};

subtest 'Verify with wrong token is rejected' => sub {
    my $ret = $user->passwd_reset_verify(
        login    => $email,
        token    => 'not-the-real-token',
        password => $new_password,
    );
    is( $ret->{msg}, 'Invalid token', 'Wrong token rejected' );
};

subtest 'Verify with expired token is rejected' => sub {
    my $login_obj = $user->logins->id( $email, ['email'] );
    my $reset     = $login_obj->settings->{reset_password};
    my $token     = $reset->{token};

    $login_obj->set_settings({ reset_password => { token => $token, expires => time() - 10 } });

    my $ret = $user->passwd_reset_verify(
        login    => $email,
        token    => $token,
        password => $new_password,
    );
    is( $ret->{msg}, 'Token expired', 'Expired token rejected' );

    # restore a valid expiry for the next subtests
    $login_obj->set_settings({ reset_password => { token => $token, expires => time() + 3600 } });
};

subtest 'Verify without password only checks token validity' => sub {
    my $login_obj = $user->logins->id( $email, ['email'] );
    my $token     = $login_obj->settings->{reset_password}->{token};

    my $ret = $user->passwd_reset_verify( login => $email, token => $token );
    is( $ret->{msg}, 'Successful', 'Token check without password does not consume the token' );

    $login_obj = $user->logins->id( $email, ['email'] );
    ok( $login_obj->settings->{reset_password}->{token}, 'Token is still present after a plain check' );
};

subtest 'Verify with a valid token actually changes the password' => sub {
    my $login_obj = $user->logins->id( $email, ['email'] );
    my $token     = $login_obj->settings->{reset_password}->{token};

    my $ret = $user->passwd_reset_verify(
        login    => $email,
        token    => $token,
        password => $new_password,
    );
    is( $ret->{msg}, 'Password reset successful', 'Reset reported as successful' );

    my $reloaded = $user->reload;
    my $stored   = $reloaded->{password};

    ok( $user->verify_password( $new_password, $stored, $email ), 'New password verifies successfully' );
    ok( !$user->verify_password( $old_password, $stored, $email ), 'Old password no longer works' );

    $login_obj = $user->logins->id( $email, ['email'] );
    is( $login_obj->settings->{reset_password}, undef, 'Token is cleared after a successful reset' );
};

subtest 'Reusing the same token a second time fails' => sub {
    my $ret = $user->passwd_reset_verify(
        login    => $email,
        token    => 'whatever-token-was-used-before',
        password => 'another_password_789',
    );
    is( $ret->{msg}, 'Invalid token', 'Token cannot be reused' );
};

subtest 'Missing params are rejected' => sub {
    my $ret = $user->passwd_reset_verify( login => $email );
    is( $ret->{msg}, 'Token is required', 'Token is required' );

    $ret = $user->passwd_reset_verify( token => 'abc' );
    is( $ret->{msg}, 'Login is required', 'Login is required' );
};

subtest 'SECURITY: reset token is never delivered to an attacker-supplied email' => sub {
    # Victim registers with a plain username (not an e-mail) and has a
    # separate, verified e-mail login — this is the setup that made the
    # bug exploitable: an attacker who knows/guesses the victim's *login*
    # could pass their own address as `email` and have the token mailed
    # to themselves instead of to the victim.
    my $victim_login    = sprintf( 'victim_user_%d', time() );
    my $victim_email    = sprintf( 'victim_real_%d@domain.ru', time() );
    my $attacker_email  = sprintf( 'attacker_%d@evil.com', time() );

    my $victim = $admin->reg(
        login    => $victim_login,
        login_type => 'login',
        password => 'victim_password_123',
    );
    ok( $victim, 'Victim registered with a username login' );

    $victim->logins->add( login => $victim_email, type => 'email' );
    my $victim_email_login = $victim->logins->id( $victim_email, ['email'] );
    ok( $victim_email_login, 'Victim email login created' );
    $victim_email_login->set_settings({ email => { verified => 1 } });

    my $ret = $victim->passwd_reset_request(
        login => $victim_login,
        email => $attacker_email,
    );
    is( $ret->{msg}, 'Successful', 'Reset request accepted' );

    my $spool = $victim->srv('spool');
    my @rows  = $spool->list;
    my ( $row ) = sort { $b->{id} <=> $a->{id} } @rows;
    ok( $row, 'A reset e-mail was queued' );

    is( $row->{settings}->{to}, $victim_email, 'Token was mailed to the victim\'s own registered address' );
    isnt( $row->{settings}->{to}, $attacker_email, 'Token was NOT mailed to the attacker-supplied address' );

    $spool->id( $row->{id} )->delete();
    $victim->delete;
};

subtest 'CORRECTNESS: reset never resolves/acts through a phone-type accounts row' => sub {
    # A `phone` login is a valid `accounts` row, but the mailed-link reset
    # flow makes no sense for it (nowhere to send the link) and must never
    # be used to resolve the account or to store/read the token — only
    # `login`/`email` typed rows are valid here.
    my $phone_user_login = sprintf( 'phoneuser_%d', time() );
    my $phone_number      = '+7 999 555-' . substr( time(), -4 );

    my $phone_user = $admin->reg(
        login    => $phone_user_login,
        login_type => 'login',
        password => 'phone_user_password_123',
    );
    ok( $phone_user, 'Phone-owning user registered with a username login' );

    $phone_user->logins->add( login => $phone_number, type => 'phone' );
    ( my $phone_digits = $phone_number ) =~ s/\D+//g;
    my $phone_login_obj = $phone_user->logins->id( $phone_digits, ['phone'] );
    ok( $phone_login_obj, 'Phone login created' );

    my $ret = $phone_user->passwd_reset_request( login => $phone_digits );
    is( $ret->{msg}, 'User not found', 'Reset request via a phone identifier is rejected outright' );

    $phone_user->delete;
};

done_testing();

exit 0;
