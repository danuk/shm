package Core::User;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    switch_user
    is_email
    passgen
    now
    get_cookies
    get_user_ip
    decode_json
);
use Core::Const;

use Digest::SHA qw(sha1_hex hmac_sha1);
use MIME::Base32;
use MIME::Base64 qw(decode_base64url encode_base64 encode_base64url);
use Math::Random::Secure qw(rand);

sub table { return 'users' };

sub structure {
    return {
        user_id => {
            type => 'number',
            key => 1,
            title => 'id пользователя',
        },
        partner_id => {
            type => 'number',
            hide_for_user => 1,
            title => 'id партнера',
        },
        login => {
            type => 'text',
            required => 1,
            title => 'логин',
        },
        password => {
            type => 'text',
            required => 1,
            hide_for_user => 1,
            title => 'пароль',
            description => 'пароль в зашифровнном виде',
        },
        type => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1,2],
            title => 'тип пользователя',
            description => '0 - физ, 1 - юр, 2 - ип',
        },
        created => {
            type => 'now',
            title => 'дата создания',
        },
        last_login => {
            type => 'date',
            title => 'дата последнего входа',
        },
        discount => {
            type => 'number',
            default => 0,
            title => 'персональная скидка',
        },
        balance => {
            type => 'number',
            default => 0,
            title => 'баланс',
        },
        credit => {
            type => 'number',
            default => 0,
            title => 'сумма кредита',
        },
        comment => {
            type => 'text',
            hide_for_user => 1,
            title => 'комментарии',
        },
        dogovor => {
            type => 'text',
            title => 'договор',
        },
        block => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг блокировки',
            description => '0 - активен, 1 - заблокирован',
        },
        gid => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'группа',
            description => '0 - пользователи, 1 - админы',
        },
        perm_credit => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг постоянного кредита',
        },
        full_name => {
            type => 'text',
            allow_update_by_user => 1,
            title => 'наименование клиента',
            description => 'произвольное значение',
        },
        can_overdraft => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг разрешения ухода в минус',
            description => '1 - разрешено уходить в минус',
        },
        bonus => {
            type => 'number',
            default => 0,
            title => 'бонусы',
        },
        phone => {
            type => 'text',
            allow_update_by_user => 1,
            title => 'номер телефона',
        },
        verified => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
            enum => [0,1],
            title => 'флаг проверки клиента',
        },
        create_act => {
            type => 'number',
            default => 1,
            hide_for_user => 1,
            enum => [0,1],
            title => 'создавать акты',
        },
        settings => {
            type => 'json',
            value => {},
            hide_for_user => 1,
            title => 'настройки клиента',
        },
    };
}

sub init {
    my $self = shift;
    my %args = (
        @_,
    );

    unless ( $self->{user_id} ) {
        $self->{user_id} = $self->user_id;
    }

    return $self;
}

sub authenticated {
    my $self = shift;
    my $config = get_service('config');
    if ( my $user_id = $config->local('authenticated_user_id') ) {
        return get_service('user', _id => $user_id );
    } else {
        return $self;
    }
}

sub events {
    return {
        'registered' => {
            event => {
                title => 'new user created',
            },
        },
        'payment' => {
            event => {
                title => 'user payment',
                kind => 'UserService',
                method => 'activate_services',
            },
        },
        'receipt' => {
            event => {
                title => 'make receipt',
                kind => 'Cloud::Jobs',
                method => 'make_receipt',
            },
        },
        'bonus' => {
            event => {
                title => 'user payment with bonuses',
                kind => 'UserService',
                method => 'activate_services',
            },
        },
        'credit' => {
            event => {
                title => 'user payment by credit',
                kind => 'UserService',
                method => 'activate_services',
            },
        },
    };
}

sub crypt_password {
    my $self = shift;
    my %args = (
        salt => undef,
        password => undef,
        @_,
    );

    return sha1_hex( join '--', $args{salt}, $args{password} );
}

sub auth_api_safe {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    my $user = $self->auth( %args );
    unless ( $user ) {
        report->status( 401 );
        report->add_error('Incorrect login or password' );
        $self->set_user_fail_attempt( 'auth_api_safe', 180 ); # 5 auth/3 min
        return;
    }

    if ( $user->is_password_auth_disabled ) {
        report->status( 403 );
        report->add_error('Password authentication is disabled.');
        return undef;
    }

    my %user_settings = $user->settings;
    if ( $user_settings{strict_ip_mode} && $user_settings{ip} ) {
        if ( $user_settings{ip} ne get_user_ip() ) {
            report->status( 403 );
            report->add_error("Login from this IP is prohibited");
            return undef;
        }
    }

    my $otp = get_service('OTP');
    if ( $otp->get_enabled($user) ) {
        unless ( $args{otp_token} ) {
            return {
                login => $user->get_login,
                otp_required => 1,
                message => 'OTP token required'
            };
        }

        unless ( $otp->verify_token( $otp->get_secret($user), $args{otp_token} ) ) {
            my $backup_valid = 0;
            if ( $otp->get_backup_codes($user) ) {
                my @backup_codes = split(',', $otp->get_backup_codes($user));
                if ( grep { $_ eq $args{otp_token} } @backup_codes ) {
                    $backup_valid = 1;
                    @backup_codes = grep { $_ ne $args{otp_token} } @backup_codes;
                    $otp->set_settings($user, backup_codes => join(',', @backup_codes));
                }
            }

            unless ( $backup_valid ) {
                return {
                    msg => 'INVALID_OTP_TOKEN',
                    status => 'fail',
                };
            }
        }

        $otp->set_settings($user, verified_at => now());
    }

    my $session_id = $user->gen_session->{id};

    return {
        id => $session_id,
    };
}

sub auth {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    $args{login} = lc( $args{login} );

    return undef unless $args{login} || $args{password};

    my $password = $self->crypt_password(
        salt => $args{login},
        password => $args{password},
    );

    my ( $user_row ) = $self->_list(
        where => {
            login => $args{login},
            password => $password,
        }
    );
    unless ( $user_row ) {
        return undef;
    }

    my $user = $self->id( $user_row->{user_id} );
    return undef if $user->is_blocked;

    return $user;
}

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

    my $password = $user->crypt_password(
        salt => $user->get_login,
        password => $args{password},
    );

    get_service('sessions')->delete_user_sessions( user_id => $self->user_id );

    $user->set( password => $password );
    return scalar $user->get;
}

sub set_new_passwd {
    my $self = shift;
    my %args = (
        len => 10,
        @_,
    );

    my $new_password = passgen( $args{len} );
    $self->passwd( password => $new_password );

    return $new_password;
}

sub gen_session {
    my $self = shift;
    my %args = (
        usi => undef,
        @_,
    );

    my $session_id = get_service('sessions')->add(
        user_id => $self->id,
        settings => {
            $args{usi} ? ( usi => $args{usi} ) : (),
        },
    );

    return {
        id => $session_id,
    };
}

sub passwd_reset_request {
    my $self = shift;
    my %args = (
        email => undef,
        login => undef,
        @_,
    );

    my $user;

    if ( $args{login} ) {
        ( $user ) = $self->_list(
            where => {
                login => $args{login},
            },
            limit => 1,
        );
    }

    if ( !$user && $args{email} && is_email($args{email}) ) {
        ( $user ) = $self->_list(
            where => {
                sprintf('%s->>"$.%s"', 'settings', 'email') => $args{email},
            },
            limit => 1,
        );

        unless ( $user ) {
            my $profile = get_service("profile");
            my ( $profile_data ) = $profile->_list(
                where => {
                    sprintf('%s->>"$.%s"', 'data', 'email') => $args{email},
                },
                limit => 1,
            );
            if ( $profile_data ) {
                $user = { user_id => $profile_data->{user_id} };
            }
        }
    }

    if ( $user ) {
        $self = $self->id( $user->{user_id} );

        if ( $self->is_blocked ) {
            return { msg => 'User is blocked' };
        }

        my $config = get_service('config');
        my $use_for_reset_password = $config->data_by_name('cli')->{use_for_reset_password};

        if ( $use_for_reset_password ) {
            my $token = passgen( 35 );
            my $expires = time() + 3600;

            $self->user->set_settings({
                reset_password_verify_token => $token,
                reset_password_verify_expires => $expires,
            });

            my $project_name = $config->data_by_name('company')->{name} || 'SHM';
            my $subject = "$project_name - Сброс пароля";
            my $url = $config->data_by_name('cli')->{url};
            my $link = $url ? "$url?token=$token" : undef;
            my $message = "Ваша ссылка для сброса пароля: $link\n\nСсылка действительна в течение часа.";

            $self->srv('spool')->add(
                event => {
                    title => 'send verify code',
                    name => 'SYSTEM',
                    server_gid => GROUP_ID_MAIL,
                },
                settings => {
                    to => $args{email},
                    subject => $subject,
                    message => $message,
                },
            );
        } else {
            $self->make_event( 'user_password_reset' );
        }

        return { msg => 'Successful' };
    }

    return { msg => 'User not found' };
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

sub set_email {
    my $self = shift;
    my %args = (
        email => undef,
        @_,
    );

    unless ( is_email($args{email}) ) {
        return { msg => 'is not email' };
    }

    my $current_email = $self->user->emails;
    if ( $current_email && $current_email eq $args{email} ) {
        return { msg => 'Successful' };
    }

    $self->user->set_settings({
        email_verified => 0,
        email => $args{email},
    });

    return { msg => 'Successful' };
}

sub verify_email {
    my $self = shift;
    my %args = (
        email => undef,
        code => undef,
        @_,
    );

    if ( $args{email} ) {
        unless ( is_email($args{email}) ) {
            return { msg => 'is not email' };
        }

        my $current_email = $self->user->emails;
        unless ( $current_email && $args{email} eq $current_email ) {
            return { msg => 'Email mismatch. Use the email shown in your profile.' };
        }

        my $code = sprintf("%06d", int(rand(1000000)));
        my $expires = time() + 600;

        $self->user->set_settings({
            email_verify_code => $code,
            email_verify_expires => $expires,
        });

        my $project_name = get_service('config')->data_by_name('company')->{name} || 'SHM';
        my $subject = "$project_name - Код подтверждения email";
        my $message = "Ваш код подтверждения: $code\n\nКод действителен 10 минут.";

        $self->srv('spool')->add(
            event => {
                title => 'send verify code',
                name => 'SYSTEM',
                server_gid => GROUP_ID_MAIL,
            },
            settings => {
                to => $args{email},
                subject => $subject,
                message => $message,
            },
        );

        return { msg => 'Verification code sent' };
    }

    if ( $args{code} ) {
        my $settings = $self->get_settings;

        unless ( $args{code} eq $settings->{email_verify_code} ) {
            return { msg => 'Invalid code' };
        }

        if ( $settings->{email_verify_expires} && $settings->{email_verify_expires} < time() ) {
            return { msg => 'Code expired' };
        }

        delete $settings->{email_verify_code};
        delete $settings->{email_verify_expires};
        $settings->{email_verified} = 1;

        $self->set( settings => $settings );

        return { msg => 'Email verified successfully' };
    }

    return { msg => 'Email or code required' };
}

sub is_blocked {
    my $self = shift;

    return $self->get_block();
}

sub validate_attributes {
    my $self = shift;
    my $method = shift;
    my %args = @_;

    my $report = get_service('report');
    return 1 if $method eq 'set';

    unless ( $args{login} ) {
        $report->add_error('Login is empty');
    }
    unless ( $args{login}=~/^[\w\d@._-]+$/ ) {
        $report->add_error('Login is short or incorrect');
    }

    unless ( $args{password} ) {
        $report->add_error('Password is empty');
    }
    if ( length $args{password} < 6 ) {
        $report->add_error('Password is short');
    }

    return $report->is_success;
}

sub reg_api_safe {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        partner_id => undef,
        @_,
    );

    my $allow_user_register_api = get_service('config')->data_by_name('billing')->{allow_user_register_api} // 1;
    unless ( $allow_user_register_api ) {
        report->status( 403 );
        report->add_error("Registration of new users is prohibited");
        return undef;
    }

    $self->set_user_fail_attempt( 'reg_api_safe', 3600 ); # 5 regs/hour

    return $self->reg(
        login => $args{login},
        password => $args{password},
        partner_id => $args{partner_id},
    );
}

sub reg {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        partner_id => undef,
        get_smart_args( @_ ),
    );

    $args{login} = lc( $args{login} );
    $args{settings}{ip} = get_user_ip();

    my $password = $self->crypt_password(
        salt => $args{login},
        password => $args{password},
    );

    my $partner_id = delete $args{partner_id} || get_cookies('partner_id');
    if ( $partner_id ) {
        $args{partner_id} = $partner_id if $self->id( $partner_id );
        delete $args{partner_id} if $partner_id == $self->id;
    }

    my $user_id = $self->add( %args, password => $password );

    unless ( $user_id ) {
        get_service('report')->add_error('Login already exists');
        return undef;
    }


    my $user = $self->id( $user_id );
    $user->make_event( 'registered' );

    return scalar $user->get;
}

sub services {
    my $self = shift;
    return get_service('UserService', user_id => $self->id );
}

sub us {
    my $self = shift;
    my $usi = shift;
    return $self->srv('us', $usi ? ( _id => $usi ) : () );
}

sub storage {
    my $self = shift;
    return $self->srv('storage');
}

sub spool {
    my $self = shift;
    return $self->srv('spool');
}

sub spool_history {
    my $self = shift;
    return $self->srv('SpoolHistory');
}

sub set {
    my $self = shift;
    my %args = (
        get_smart_args( @_ ),
    );

    if ( $args{block} ) {
        get_service('sessions')->delete_user_sessions( user_id => $self->user_id );
    }

    if (( defined $args{credit} && $args{credit} > 0 && $self->get_credit != $args{credit} )
        || $args{perm_credit}
    ){
        $self->make_event( 'credit', settings => { credit => $args{credit} } );
    }

    return $self->SUPER::set( %args );
}

sub set_balance {
    my $self = shift;
    my %args = (
        balance => 0,
        bonus => 0,
        @_,
    );

    my @keys = sort keys %args;
    my @values = @args{@keys};

    my $data = join(',', map { "$_=$_+?" } @keys);
    my $ret = $self->do("UPDATE users SET $data WHERE user_id=?", @values, $self->id);

    $self->reload() if $ret;

    return $ret;
}

sub set_bonus {
    my $self = shift;
    my %args = (
        bonus => 0,
        comment => undef,
        get_smart_args( @_ ),
    );

    return undef if !$args{bonus} || $args{bonus} == 0;

    my $bonus_id = $self->bonus->add( %args );

    $self->set_balance( bonus => $args{bonus} );
    $self->make_event( 'bonus', settings => { bonus_id => $bonus_id } ) if $args{bonus} > 0;

    return $bonus_id;
}

sub set_credit {
    my $self = shift;
    my $credit = shift;

    $self->make_event( 'credit', settings => { credit => $credit } ) if defined $credit && $credit > 0;
    return $self->set( credit => $credit );
}

# method for api
sub add_bonus {
    my $self = shift;
    my $bonus = shift;
    my $comment = shift;

    if ( $comment && !ref $comment ) {
        $comment = { msg => $comment };
    }

    return $self->set_bonus(
        bonus => $bonus,
        comment => $comment,
    );
}

sub payment {
    my $self = shift;
    my %args = (
        money => 0,
        currency => undef,
        uniq_key => undef,
        get_smart_args( @_ ),
    );

    if ( $args{user_id} ) {
        switch_user( $args{user_id} );
        $self = $self->id( $args{user_id} );
    }

    my $pays = $self->pays;
    my $pay_id;
    unless ( $pay_id = $pays->add( %args ) ) {
        get_service('report')->add_error("Can't make a payment");
        $self->logger->error( %args );
        return undef;
    }

    $self->set_balance( balance => $args{money} );
    $self->add_bonuses_for_partners( $args{money} ) if $args{money} && $args{money} > 0;

    $self->make_event( 'payment', settings => { pay_id => $pay_id } );

    my $srv_customlab_nalog = get_service('config')->id( 'pay_systems' )->get_data->{'srv_customlab_nalog'};
    if ( $srv_customlab_nalog && $srv_customlab_nalog->{enabled} ) {
        $self->make_event( 'receipt', settings => { pay_id => $pay_id } ) if $args{money} && $args{money} > 0;
    }

    return scalar $pays->id( $pay_id )->get;
}

sub recash {
    my $self = shift;

    my %before = $self->get;

    my $money_total = $self->pays->sum->{money} // 0;
    my $bonus_total = $self->bonus->sum->{bonus} // 0;

    my $wd_sum = $self->wd->sum // 0;
    my $wd_total = $wd_sum->{total};
    my $wd_bonus = $wd_sum->{bonus};

    my $balance = $money_total - $wd_total;
    my $bonus = $bonus_total - $wd_bonus;

    $self->set(
        balance => $balance,
        #bonus => $bonus,
        bonus => $bonus_total, # calc bonuses by the bonus table, because it also contains withdraws data
    );

    return {
        before => {
            balance => sprintf("%.2f", $before{balance} ),
            bonus => sprintf("%.2f", $before{bonus} ),
        },
        after => {
            balance => sprintf("%.2f", $self->balance ),
            bonus => sprintf("%.2f", $self->get_bonus ),
        },
        delta => {
            balance => sprintf("%.2f", $self->balance - $before{balance}),
            bonus => sprintf("%.2f", $self->get_bonus - $before{bonus}),
        }
    };
}

sub add_bonuses_for_partners {
    my $self = shift;
    my $payment = shift;

    if ( my $partner = $self->partner ) {
        my $percent = $partner->income_percent;
        my $bonus = $payment * $percent / 100;
        $partner->set_bonus( bonus => $bonus,
            comment => {
                from_user_id => $self->id,
                payment => $payment,
                percent => $percent,
            },
        ) if $bonus;
    }
}

sub delete {
    my $self = shift;
    my %args = (
        force => 0,
        get_smart_args( @_ ),
    );

    my $report = get_service('report');

    if ( $self->is_admin ) {
        $report->add_error("Can't delete admin");
        return undef;
    }

    unless ( $args{force} ) {
        if ( $self->get_balance ) {
            $report->add_error("Can't delete user with non-zero balance");
            return undef;
        }

        my @usi = $self->services->list_for_api();
        if ( scalar @usi ) {
            $report->add_error("Can't delete user with services");
            return undef;
        }
    }

    my @objects = qw(
        UserService
        withdraw
        bonus
        pay
        profile
        storage
        spool
        SpoolHistory
        sessions
        Acts
        ActsData
        promo
    );

    get_service( $_, user_id => $self->id )->delete_all for @objects;

    return $self->SUPER::delete();
}

*pay = \&pays;

sub pays {
    my $self = shift;
    return $self->srv('pay');
}

sub has_payments {
    my $self = shift;
    return $self->pays->last ? 1 : 0;
}

sub has_withdraws {
    my $self = shift;
    return $self->wd->last ? 1 : 0;
}

sub has_services {
    my $self = shift;
    return $self->us->has_services;
}

sub bonus {
    my $self = shift;
    return get_service('bonus', user_id => $self->id );
}

*wd = \&withdraws;

sub withdraws {
    my $self = shift;
    return get_service('withdraw', user_id => $self->id );
}

sub promo {
    my $self = shift;
    return get_service('promo', user_id => $self->id );
}

sub is_admin {
    my $self = shift;
    return $self->get_gid;
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        filter => {},
        where => {},
        @_,
    );

    if ( $args{filter}->{settings} ) {
        $args{where}->{settings} = { '-like' => delete $args{filter}->{settings} };
    }

    if ( $args{admin} ) {
        $args{where}->{user_id} = $args{user_id} if $args{user_id};
    } else {
        $args{where}->{user_id} = $self->id;
    }

    my @result = $self->SUPER::list_for_api( %args );

    for my $item (@result) {
        $item->{email} = $self->id( $item->{user_id} )->emails || '';
        $item->{email_verified} = $self->id( $item->{user_id} )->get_settings->{email_verified} || 0;
    }

    return @result;
}

sub _list {
    my $self = shift;
    my %args = (
        where => {},
        get_smart_args( @_ ),
    );

    unless ( exists $args{where}{ sprintf("%s.%s", $self->table, $self->get_table_key ) } ||
             exists $args{where}{ $self->get_table_key }
    ) {
        $args{where}->{block} //= 0;
    }

    return $self->SUPER::_list( %args );
}

sub profile {
    my $self = shift;

    my $profile = get_service("profile");
    my ( $item ) = $profile->_list(
        where => {
            user_id => $self->id,
        },
        limit => 1,
    );

    return %{ $item->{data} || {} };
}

sub emails {
    my $self = shift;

    my %profile = $self->profile;
    my $email = $profile{email} || $self->get_settings->{email} || $self->get_login;

    return is_email($email) ? $email : undef;
}

sub referrals {
    my $self = shift;

    return $self->items(
        where => {
            partner_id => $self->id,
        },
    );
}

sub referrals_count {
    my $self = shift;

    my @count = $self->_list(
        where => {
            partner_id => $self->id,
        },
    );

    return scalar @count;
}

sub switch {
    my $self = shift;
    my $user_id = shift;

    if ( my $user = $self->id( $user_id ) ) {
        switch_user( $user->id );
        return $user;
    }
    return undef;
}

sub delete_autopayment {
    my $self = shift;
    my %args = (
        pay_system => undef,
        @_,
    );

    my $pay_system = $args{pay_system};

    my $settings = $self->get_settings;

    if ($pay_system) {
        delete $settings->{pay_systems}->{$pay_system};
    } else {
        delete $settings->{pay_systems};
    }

    $self->set( settings => $settings );
    return {
        success => 1,
    }
}

sub income_percent {
    my $self = shift;

    my $percent = 0;

    my $p_settings = $self->get_settings->{partner};
    if ( exists $p_settings->{income_percent} ) {
        return $p_settings->{income_percent} || 0;
    }

    return get_service('config')->data_by_name('billing')->{partner}->{income_percent} || 0;
}

sub list_autopayments {
    my $self = shift;

    my $config = get_service('config', _id => 'pay_systems') or return {};
    my $ps = $config->get_data || {};
    my $pay_systems = $self->get_settings->{pay_systems} || {};

    for ( keys %$pay_systems ) {
        delete $pay_systems->{ $_ } unless $ps->{ $_ }->{allow_recurring};
    }
    return $pay_systems || {};
}

sub has_autopayment {
    my $self = shift;
    return keys %{ $self->list_autopayments };
}

sub make_autopayment {
    my $self = shift;
    my $amount = shift;

    return undef unless $amount;
    return undef if $self->get_settings->{deny_auto_payments};

    my $session_id = $self->gen_session->{id};
    my $transport = get_service('Transport::Http');

    my %pay_systems = %{ $self->list_autopayments };
    return undef unless %pay_systems;

    for my $name ( keys %pay_systems ) {
        my $response = $transport->http(
            url => sprintf("%s/shm/pay_systems/%s.cgi",
                get_service('config')->data_by_name('api')->{url},
                $name,
            ),
            method => 'post',
            headers => {
                session_id => $session_id,
            },
            content => {
                action => 'payment',
                amount => $amount,
                $pay_systems{ $name },
            },
        );

        if ( $response->is_success ) {
            return 1;
        }
    }
    return 0;
}

sub active_count {
    my $self = shift;

    if ( my $cnt = $self->cache->get('shm_active_users_count') ) {
        return $cnt;
    }

    my ($cnt) = $self->dbh->selectrow_array("
        SELECT COUNT(DISTINCT us.user_id)
        FROM user_services AS us
        INNER JOIN withdraw_history AS wd ON us.withdraw_id = wd.withdraw_id
        WHERE
            us.status = 'ACTIVE' AND
            us.expire IS NOT NULL AND
            (wd.bonus > 0 OR wd.total > 0)
        "
    );

    $self->cache->set('shm_active_users_count', $cnt, 86400);

    return $cnt || 0;
}

sub telegram { shift->srv('Transport::Telegram') };

sub partner {
    my $self = shift;

    my $partner_id = $self->get_partner_id;
    return undef unless $partner_id;

    return $self->id( $partner_id );
}

sub is_password_auth_disabled {
    my $self = shift;
    return $self->get_settings->{password_auth_disabled} || 0;
}

sub api_disable_password_auth {
    my $self = shift;

    my $report = get_service('report');

    my $passkey = get_service('Passkey');
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

    my $passkey = get_service('Passkey');
    my $otp = get_service('OTP');

    return {
        password_auth_disabled => $self->is_password_auth_disabled ? 1 : 0,
        passkey_enabled => $passkey->get_enabled($self) ? 1 : 0,
        otp_enabled => $otp->get_enabled($self) ? 1 : 0,
    };
}

1;
