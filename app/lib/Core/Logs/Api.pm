package Core::Logs::Api;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;

sub table { return 'logs_api' }
sub dbh { shift->dbh_auto_commit }

sub structure {
    return {
        user_id => {
            type => 'number',
            auto_fill => 1,
            title => 'id пользователя',
        },
        date => {
            type => 'now',
            title => 'дата',
        },
        url => {
            type => 'text',
            required => 1,
            title => 'URL',
        },
        method => {
            type => 'text',
            required => 1,
            title => 'метод',
        },
        args => {
            type => 'json',
            title => 'аргументы',
        },
        descr => {
            type => 'text',
            title => 'описание',
        },
        duration => {
            type => 'number',
            default => 0,
            title => 'продолжительность',
        },
        response_code => {
            type => 'number',
            required => 1,
            title => 'код ответа',
        },
        ip => {
            type => 'text',
            title => 'IP адрес',
        },
        response_error => {
            type => 'text',
            title => 'ошибка',
        },
    }
}

sub add {
    my $self = shift;
    my %args = (
        url => undef,
        method => undef,
        args => {},
        response_code => undef,
        duration => 0,
        @_,
    );

    if ( ref $args{args} eq 'HASH' ) {
        my %masked = %{ $args{args} };
        my %sensitive = map { $_ => 1 } qw(
            password token otp_token session_id secret
            private_key hash code id_token code_verifier
            client_secret nonce captcha_token captcha_answer
        );
        for my $key ( keys %masked ) {
            $masked{$key} = '***' if $sensitive{ lc $key };
        }
        $args{args} = \%masked;
    }

    $self->{user_id} = 0 unless $self->user_id;

    return $self->SUPER::add( %args );
}

sub cleanup {
    my $self = shift;
    my $days = cfg('billing')->{cleanup}->{ApiLogs} // 30;
    return $self unless $days;

    $self->_delete( where => {
        date => { '<', \[ 'NOW() - INTERVAL ? DAY', $days ] },
    });

    return $self;
}

1;
