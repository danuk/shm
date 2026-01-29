package Core::OTP;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(now);
use Digest::SHA qw(hmac_sha1);
use MIME::Base32;
use Math::Random::Secure qw(rand);

sub table { return 'users' };

sub generate_secret {
    my $self = shift;

    my $secret = '';
    for (1..16) {
        $secret .= chr(int(rand(256)));
    }

    return MIME::Base32::encode($secret);
}

sub verify_token {
    my $self = shift;
    my ($secret, $token, $window) = @_;
    $window ||= 1; # Окно в 30 секунд в каждую сторону

    my $current_time = int(time() / 30);

    for my $i (-$window..$window) {
        my $time_step = $current_time + $i;
        my $expected_token = $self->_generate_totp($secret, $time_step);

        if ($token eq $expected_token) {
            return 1;
        }
    }

    return 0;
}

sub _generate_totp {
    my $self = shift;
    my ($secret, $time_step) = @_;

    my $decoded_secret = MIME::Base32::decode($secret);
    my $time_bytes = pack('N2', 0, $time_step);

    my $hash = hmac_sha1($time_bytes, $decoded_secret);

    my $offset = ord(substr($hash, -1)) & 0x0f;
    my $code = unpack('N', substr($hash, $offset, 4)) & 0x7fffffff;

    return sprintf('%06d', $code % 1000000);
}

sub generate_backup_codes {
    my $self = shift;

    my @codes;
    for (1..10) {
        my $code = sprintf('%08d', int(rand(100000000)));
        push @codes, $code;
    }

    return @codes;
}

sub get_enabled {
    my $self = shift;
    return $self->user->get_settings->{otp}->{enabled} || 0;
}

sub get_secret {
    my $self = shift;
    return $self->user->get_settings->{otp}->{secret};
}

sub get_backup_codes {
    my $self = shift;
    return $self->user->get_settings->{otp}->{backup_codes};
}

sub get_verified_at {
    my $self = shift;
    return $self->user->get_settings->{otp}->{verified_at};
}

sub api_setup {
    my $self = shift;

    if ($self->get_enabled()) {
        report->add_error('OTP_ALREADY_ENABLED');
        return undef;
    }

    my $secret = $self->generate_secret();
    my @backup_codes = $self->generate_backup_codes();

    $self->user->set_settings({ otp => {
        secret => $secret,
        backup_codes => join(',', @backup_codes),
        enabled => 0
    }});

    my $project_name = get_service('config')->data_by_name('project')->{name} || 'SHM';
    my $qr_url = sprintf(
        'otpauth://totp/%s:%s?secret=%s&issuer=%s',
        $project_name, $self->get_login, $secret, $project_name
    );

    return {
        qr_url => $qr_url,
        secret => $secret,
        backup_codes => \@backup_codes
    };
}

sub api_enable {
    my $self = shift;
    my %args = (
        token => undef,
        @_,
    );

    unless ($args{token}) {
        report->add_error('TOKEN_REQUIRED');
        return undef;
    }

    my $secret = $self->get_secret();
    unless ($secret) {
        report->add_error('OTP_NOT_SETUP');
        return undef;
    }

    unless ($self->verify_token($secret, $args{token})) {
        report->add_error('INVALID_TOKEN');
        return undef;
    }

    $self->user->set_settings({ otp => { enabled => 1 } });

    return { success => 1 };
}

sub api_disable {
    my $self = shift;
    my %args = (
        token => undef,
        @_,
    );

    unless ($args{token}) {
        report->add_error('TOKEN_REQUIRED');
        return undef;
    }

    unless ($self->get_enabled()) {
        report->add_error('OTP_NOT_ENABLED');
        return undef;
    }

    my $valid = 0;
    if ($self->verify_token($self->get_secret(), $args{token})) {
        $valid = 1;
    } elsif ($self->get_backup_codes()) {
        my @backup_codes = split(',', $self->get_backup_codes());
        if (grep { $_ eq $args{token} } @backup_codes) {
            $valid = 1;
            @backup_codes = grep { $_ ne $args{token} } @backup_codes;
            $self->user->set_settings({ otp => { backup_codes => join(',', @backup_codes) } });
        }
    }

    unless ($valid) {
        report->add_error('INVALID_TOKEN');
        return undef;
    }

    my $settings = $self->user->get_settings;
    delete $settings->{otp};
    $self->user->set(settings => $settings);

    return { success => 1 };
}

sub api_verify {
    my $self = shift;
    my %args = (
        token => undef,
        @_,
    );

    unless ($args{token}) {
        report->add_error('TOKEN_REQUIRED');
        return undef;
    }

    unless ($self->get_enabled()) {
        report->add_error('OTP_NOT_ENABLED');
        return undef;
    }

    my $valid = 0;
    if ($self->verify_token($self->get_secret(), $args{token})) {
        $valid = 1;
    } elsif ($self->get_backup_codes()) {
        my @backup_codes = split(',', $self->get_backup_codes());
        if (grep { $_ eq $args{token} } @backup_codes) {
            $valid = 1;
            @backup_codes = grep { $_ ne $args{token} } @backup_codes;
            $self->user->set_settings({ otp => { backup_codes => join(',', @backup_codes) } });
        }
    }

    if ($valid) {
        $self->user->set_settings({ otp => { verified_at => now() } });
        return { verified => 1 };
    }

    report->add_error('INVALID_TOKEN');
    return undef;
}

sub api_status {
    my $self = shift;

    my $enabled = $self->get_enabled() || 0;

    my $verified = 0;
    my $required = 0;

    if ($enabled && $self->get_verified_at()) {
        my $verification_timeout = 24 * 60 * 60;
        my $last_verified = $self->get_verified_at();

        my $verified_timestamp;
        if ($last_verified =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
            use Time::Local;
            $verified_timestamp = timelocal($6, $5, $4, $3, $2-1, $1);

            my $time_diff = time() - $verified_timestamp;
            if ($time_diff < $verification_timeout) {
                $verified = 1;
                $required = 0;
            } else {
                $verified = 0;
                $required = 1;
            }
        } else {
            $verified = 0;
            $required = 1;
        }
    } elsif ($enabled) {
        $verified = 0;
        $required = 1;
    }

    return {
        enabled => $enabled ? 1 : 0,
        verified => $verified,
        required => $required,
        last_verified => $self->get_verified_at()
    };
}

1;
