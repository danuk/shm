package Core::Auth::OAuth2::Yandex;

use v5.14;
use Core::Base;

sub yandex_config {
    return {
        authorize_endpoint => 'https://oauth.yandex.ru/authorize',
        token_endpoint     => 'https://oauth.yandex.ru/token',
        userinfo_endpoint  => 'https://login.yandex.ru/info',
        verify_mode        => 'userinfo',
        base_scope         => 'login:email',
        field_scopes       => {
            email    => 'login:email',
            profile  => 'login:info',
            avatar   => 'login:avatar',
            birthday => 'login:birthday',
            phone    => 'login:default_phone',
        },
    };
}

sub yandex_normalize_claims {
    my $self = shift;
    my $raw = shift || {};

    my $email = $raw->{default_email}
        || $raw->{email}
        || ( ref $raw->{emails} eq 'ARRAY' ? $raw->{emails}[0] : undef )
        || $raw->{defaultEmail};

    my $avatar = ( !$raw->{is_avatar_empty} && $raw->{default_avatar_id} )
        ? sprintf('https://avatars.yandex.net/get-yapic/%s/islands-200', $raw->{default_avatar_id})
        : undef;
    my $phone = ref $raw->{default_phone} eq 'HASH' ? $raw->{default_phone}{number} : undef;

    return {
        subject => $raw->{id} || $raw->{uid},
        email => {
            address => $email,
            verified => 1,
        },
        name => $raw->{real_name} || $raw->{display_name} || $raw->{first_name} || $raw->{last_name},
        first_name => $raw->{first_name},
        last_name => $raw->{last_name},
        picture => $avatar,
        phone => $phone,
        birthday => $raw->{birthday},
    };
}

1;
