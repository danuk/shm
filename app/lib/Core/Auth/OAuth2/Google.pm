package Core::Auth::OAuth2::Google;

use v5.14;
use Core::Base;

sub google_config {
    return {
        issuer             => 'https://accounts.google.com',
        authorize_endpoint => 'https://accounts.google.com/o/oauth2/v2/auth',
        token_endpoint     => 'https://oauth2.googleapis.com/token',
        jwks_uri           => 'https://www.googleapis.com/oauth2/v3/certs',
        verify_mode        => 'id_token',
        base_scope         => 'openid',
        field_scopes       => { email => 'email', profile => 'profile' },
    };
}

sub google_normalize_claims {
    my $self = shift;
    my $raw = shift || {};

    return {
        subject => $raw->{sub},
        email => {
            address => $raw->{email},
            verified => $raw->{email_verified} ? 1 : 0,
        },
        name => $raw->{name},
        first_name => $raw->{given_name},
        last_name => $raw->{family_name},
        picture => $raw->{picture},
    };
}

1;
