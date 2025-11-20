package Core::Cloud;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    encode_json
    decode_json
    encode_base64
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

sub cloud_request {
    my $self = shift;
    my %args = (
        @_,
    );

    my $auth =  $self->get_auth();
    unless ( $auth ) {
        report->status( 201 );
        report->add_error('Not authorized in cloud. Please, login first' );
        return undef;
    }

    $args{headers}->{Authorization} = sprintf("Basic %s", $auth );
    $args{url} = CLOUD_URL . $args{url};

    my $response = $self->http( %args );

    unless ( $response->is_success ) {
        report->status( 400 ); # do not use 401 code because it reserves by Web
        report->add_error( $response->decoded_content );
        return undef;
    }

    return $response;
}

sub config {
    my $self = shift;
    return get_service('config', _id => '_shm');
}

sub get_auth {
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

sub save_auth {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    if ( $args{login} && $args{password} ) {
        $self->config->set_value({
            cloud => {
              auth => $self->get_auth( login => $args{login}, password => $args{password} ),
            }
        });
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
        url => CLOUD_URL . '/user/auth',
        method => 'post',
        content => {
            login    => $args{login},
            password => $args{password},
        },
    );

    unless ( $response->is_success ) {
        report->status( 400 ); # do not use 401 code because it reserves by Web
        report->add_error('Incorrect login or password' );
        return undef;
    }

    $self->save_auth(
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

    my $response = $self->cloud_request(
        url => '/user',
        method => 'put',
        content => {
            login    => $args{login},
            password => $args{password},
        },
    );

    if ( $response->is_success ) {
        $self->save_auth(
            login    => $args{login},
            password => $args{password},
        );
    }
    return $response->json_content->{data};
}

sub logout_user {
    my $self = shift;

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

    return $response ? $response->json_content->{data} : undef;
}

1;
