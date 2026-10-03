package Core::Cloud;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    encode_json
    decode_json
    encode_base64
    parse_args
    encode_base64url
    decode_base64url
);

use constant {
    CLOUD_URL => 'https://cloud.myshm.ru',
};

sub http {
    my $self = shift;
    my %args = (
        url     => CLOUD_URL,
        method  => 'get',
        headers => {},
        content => {},
        @_,
    );

    my $transport = get_service('Core::Transport::Http');
    return $transport->http(%args);
}

sub check_network {
    my $self = shift;

    my $response = $self->http(
        url => CLOUD_URL . '/test',
        method => 'get',
    );
    return $response && $response->is_success ? 1 : 0;
}

sub get_auth_header {
    my $self = shift;
    my $auth_header;

    if ( my $token = $self->get_auth_token ) {
        $auth_header = sprintf("Bearer %s", $token );
    } elsif ( my $auth = $self->get_auth_basic ) {
        $auth_header = sprintf("Basic %s", $auth );
    }

    return $auth_header;
}

sub cloud_request {
    my $self = shift;
    my %args = (
        @_,
    );

    $args{headers} = $self->cloud_headers;

    if ( my $auth_header = $self->get_auth_header ) {
        $args{headers}->{Authorization} = $auth_header;
    } else {
        report->status( 400 );
        return undef;
    }

    $args{url} = CLOUD_URL . $args{url};

    my $response = $self->http( %args );
    my $status_code = $response->code;

    unless ( $response->is_success ) {
        my $err = $response->json_content ? $response->json_content->{error} : $response->decoded_content;
        if ( $status_code == 401 ) { # && $err eq 'Account restricted' ) {
            $err = 'IP prohibited'; # Message for Web
        }

        report->status( 400 ); # do not use 401 code because it reserves by Web
        report->add_error( $err || 'ERROR' );
    }

    return $response;
}

sub config {
    my $self = shift;
    return get_service('config', _id => '_shm');
}

sub get_auth_basic {
    my $self = shift;
    return $self->config->get_data->{cloud}->{auth};
}

sub get_auth_token {
    my $self = shift;
    my $token = $self->config->get_data->{cloud}->{token};
    return $token ? decode_base64url( $token ) : '';
}

sub save_auth_basic {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    if ( $args{login} && $args{password} ) {
        $self->config->set_value({
            cloud => {
              auth => encode_base64 sprintf("%s:%s", $args{login}, $args{password} ),
            }
        });
        $self->srv('Cloud::Jobs')->startup();
    }
}

sub save_auth_token {
    my $self = shift;
    my %args = (
        token => undef,
        @_,
    );

    return undef unless $args{token};

    $self->config->set_value({
        cloud => {
            auth => undef, # remove legacy basic auth if exists
            token => encode_base64url( $args{token} ),
        }
    });
    $self->srv('Cloud::Jobs')->startup();

    return 1;
}

sub get_user {
    my $self = shift;

    my $response = $self->cloud_request(
        url => '/cloud/info',
        method => 'get',
    ) || return undef;

    unless ( $response->is_success ) {
        report->status( 400 );
        report->add_error( $response->decoded_content || 'ERROR' );
        return undef;
    }

    return $response->json_content || $response->decoded_content;
}

sub reg {
    my $self = shift;
    my %args = (
        login => undef,
        login_type => 'email',
        password => undef,
        captcha_token => undef,
        captcha_answer => undef,
        @_,
    );

    my $response = $self->http(
        url => CLOUD_URL . '/cloud/user/reg',
        method => 'put',
        content => {
            login    => $args{login},
            login_type => $args{login_type},
            password => $args{password},
            captcha_token => $args{captcha_token},
            captcha_answer => $args{captcha_answer},
        },
    );

    unless ( $response->is_success ) {
        return undef;
    }

    my $answer = $response->json_content || {};

    if ( $answer->{token} ) {
        $self->save_auth_token(
            token => $answer->{token},
        );
    } else {
        $self->save_auth_basic(
            login    => $args{login},
            password => $args{password},
        );
    }

    return { successful => 1 };
}

sub auth {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    my $response = $self->http(
        url => CLOUD_URL . '/cloud/user/auth',
        method => 'get',
        content => {
            login    => $args{login},
            password => $args{password},
        },
    );

    unless ( $response->is_success ) {
        my $error = $response->json_content->{error};
        my $status_code = $response->code;
        $status_code = 400 if $status_code == 401; # do not use 401 code because it reserves by Web
        report->status( $status_code );
        report->add_error( $error || 'ERROR' );
        return undef;
    }

    my $response = $response->json_content || {};

    if ( $response->{token} ) {
        $self->save_auth_token(
            token => $response->{token},
        );
    } else {
        $self->save_auth_basic(
            login    => $args{login},
            password => $args{password},
        );
    }

    return { successful => 1 };
}

sub logout {
    my $self = shift;

    get_service('Cloud::Subscription')->clear_subscription_cache();

    $self->config->set_value({
        cloud => {
            auth => undef,
        }
    });

    return undef;
}

sub proxy {
    my $self = shift;
    my %args = (
        uri => undef,
        method => undef,
        headers => {},
        parse_args(),
        @_,
    );

    my $headers = delete $args{headers};
    $headers->{content_type} ||= 'application/json; charset=utf-8';

    my $method = uc( $args{method} || $ENV{REQUEST_METHOD} );
    $headers = $self->cloud_headers;

    if ( my $auth = $self->get_auth_header ) {
        $headers->{Authorization} = $auth;
    }

    my $response = $self->http(
        url => CLOUD_URL . '/' . $args{uri},
        method => $method,
        headers => $headers,
        content => \%args,
    );

    unless ( $response->is_success ) {
        my $error;
        if ( my $json = $response->json_content ) {
            $error = $json->{error};
        } else {
            $error = $response->decoded_content;
        }
        my $status_code = $response->code;
        $status_code = 400 if $status_code == 401; # do not use 401 code because it reserves by Web
        report->status( $response->code );
        report->add_error( $error || 'ERROR' );
        return undef;
    }

    return $response->json_content || $response->decoded_content;
}

sub reset_user_ip {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    my $response = $self->cloud_request(
        url => '/cloud/user/reset',
        method => 'post',
        content => {
            login    => $args{login},
            password => $args{password},
        },
    ) || return undef;

    unless ( $response->is_success ) {
        report->status( 400 );
        report->add_error( $response->decoded_content || 'ERROR' );
        return undef;
    }

    return $response->json_content || $response->decoded_content;
}

sub paysystems {
    my $self = shift;

    my $response = $self->cloud_request(
        url => '/user/pay/paysystems',
    );

    return $response && $response->is_success ? $response->json_content->{data} : undef;
}

sub ps_list {
    my $self = shift;

    my %ps;
    my $config = get_service("config", _id => 'pay_systems');
    my %list = %{ $config ? $config->get_data : {} };
    for ( keys %list ) {
        next if $_ eq 'manual';
        $ps{ $list{ $_ }->{paysystem} || $_ } = 1;
    }

    return keys %ps;
}

1;
