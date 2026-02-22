package Core::Cloud;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    encode_json
    decode_json
    encode_base64
    parse_args
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

sub cloud_request {
    my $self = shift;
    my %args = (
        @_,
    );

    my $auth =  $self->get_auth_basic();
    unless ( $auth ) {
        report->status( 400 );
        return undef;
    }

    $args{headers} = $self->cloud_headers;
    $args{headers}->{Authorization} = sprintf("Basic %s", $auth );
    $args{url} = CLOUD_URL . $args{url};

    my $response = $self->http( %args );

    unless ( $response->is_success ) {
        report->status( 400 ); # do not use 401 code because it reserves by Web
        my $err = $response->json_content ? $response->json_content->{error} : $response->decoded_content;
        report->add_error( $err );
    }

    return $response;
}

sub config {
    my $self = shift;
    return cfg('_shm');
}

sub get_auth_basic {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    if ( $args{login} && $args{password} ) {
        return encode_base64( sprintf("%s:%s", $args{login}, $args{password}) );
    }

    return $self->config->get_data->{cloud}->{auth};
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
              auth => $self->get_auth_basic( login => $args{login}, password => $args{password} ),
            }
        });
        $self->srv('Cloud::Jobs')->startup();
    }
}

sub get_user {
    my $self = shift;

    my $response = $self->cloud_request(
        url => '/user',
        method => 'get',
    ) || return undef;

    unless ( $response->is_success ) {
        report->status( 400 );
        report->add_error( $response->decoded_content );
        return undef;
    }

    return $response->json_content->{data}->[0];
}

sub login_user {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    my $response = $self->http(
        url => CLOUD_URL . '/auth',
        method => 'get',
        headers => {
            ps => join(',', $self->ps_list),
        },
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
        report->add_error( $error );
        return undef;
    }

    $self->save_auth_basic(
        login    => $args{login},
        password => $args{password},
    );

    return $self->get_user();
}

sub reg_user {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    my $response = $self->http(
        url => CLOUD_URL . '/user',
        method => 'put',
        content => {
            login    => $args{login},
            password => $args{password},
        },
    );

    unless ( $response->is_success ) {
        return undef;
    }

    $self->save_auth_basic(
        login    => $args{login},
        password => $args{password},
    );

    return $response->json_content->{data};
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

    if ( my $auth =  $self->get_auth_basic() ) {
        $headers = $self->cloud_headers;
        $headers->{Authorization} = sprintf("Basic %s", $auth );
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
        report->add_error( $error );
        return undef;
    }

    return $response->json_content || $response->decoded_content;
}

sub logout_user {
    my $self = shift;

    get_service('Cloud::Subscription')->clear_subscription_cache();

    $self->config->set_value({
        cloud => {
            auth => undef,
        }
    });

    return undef;
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
