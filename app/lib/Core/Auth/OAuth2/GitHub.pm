package Core::Auth::OAuth2::GitHub;

use v5.14;
use Core::Base;

sub github_config {
    return {
        authorize_endpoint => 'https://github.com/login/oauth/authorize',
        token_endpoint     => 'https://github.com/login/oauth/access_token',
        userinfo_endpoint  => 'https://api.github.com/user',
        emails_endpoint    => 'https://api.github.com/user/emails',
        verify_mode        => 'userinfo',
        userinfo_auth      => 'bearer',
        user_agent         => 'SHM',
        base_scope         => 'read:user',
        field_scopes       => { email => 'user:email', profile => 'read:user' },
    };
}

sub github_normalize_claims {
    my $self = shift;
    my $raw = shift || {};

    my $email = $raw->{email};
    my $verified = $email ? 1 : 0;

    if ( !$email && ref $raw->{__emails} eq 'ARRAY' ) {
        my ($primary) = grep { ref($_) eq 'HASH' && $_->{primary} } @{ $raw->{__emails} };
        $primary ||= $raw->{__emails}[0];
        if ( ref $primary eq 'HASH' ) {
            $email = $primary->{email};
            $verified = $primary->{verified} ? 1 : 0;
        }
    }

    my ( $first_name, $last_name ) = split /\s+/, ( $raw->{name} || '' ), 2;

    return {
        subject => $raw->{id},
        email => {
            address => $email,
            verified => $verified,
        },
        name => $raw->{name} || $raw->{login},
        first_name => $first_name,
        last_name => $last_name,
        picture => $raw->{avatar_url},
    };
}

1;
