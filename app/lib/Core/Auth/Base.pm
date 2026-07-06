package Core::Auth::Base;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::System::ServiceManager qw( get_service );
use URI::Escape qw( uri_escape );

sub provider_names {
    my $self = shift;
    my @providers = @_ ? @_ : ( OAUTH2_PROVIDERS );
    return sort grep { $self->can("${_}_config") } @providers;
}

sub provider_config {
    my $self = shift;
    my $provider = shift || return undef;
    my $method = "${provider}_config";
    return $self->can($method) ? $self->$method() : undef;
}

sub normalize_claims {
    my $self = shift;
    my $provider = shift;
    my $raw = shift || {};
    my $method = "${provider}_normalize_claims";
    return $self->can($method) ? $self->$method($raw) : {};
}

sub provider_fields {
    my $self = shift;
    my $provider = shift;
    my $cfg = $self->can('oauth2_config') ? $self->oauth2_config($provider) : {};
    $cfg = $self->can('oidc_config') ? $self->oidc_config($provider) : $cfg if ref($cfg) ne 'HASH';

    my $fields = $cfg->{fields};
    return ref $fields eq 'ARRAY' && @$fields ? $fields : ['email'];
}

sub provider_scope {
    my $self = shift;
    my $provider = shift;

    my $pcfg = $self->provider_config($provider) || return '';
    my %requested = map { $_ => 1 } @{ $self->provider_fields($provider) };
    $requested{email} = 1; # email always required

    my @scopes = ( $pcfg->{base_scope} || () );
    for my $field ( sort keys %requested ) {
        push @scopes, $pcfg->{field_scopes}{$field} if $pcfg->{field_scopes}{$field};
    }
    return join(' ', grep { length } @scopes);
}

sub http_transport {
    my $self = shift;
    return $self->{http_transport} ||= get_service('Transport::Http');
}

sub callback_url {
    my $self = shift;
    my $provider = shift;
    my $prefix = shift || 'oauth2';

    my $scheme = $ENV{HTTP_X_FORWARDED_PROTO}
        || ( ($ENV{HTTPS} || '') =~ /^(1|on)$/i ? 'https' : 'http' );
    my $host = $ENV{HTTP_X_FORWARDED_HOST} || $ENV{HTTP_HOST} || 'localhost';

    return sprintf('%s://%s/shm/v1/%s/callback/%s', $scheme, $host, $prefix, $provider);
}

sub auth_state_cache_key {
    my $self = shift;
    my $state = shift;
    my $prefix = shift || 'auth_state';
    return sprintf('%s_%s', $prefix, $state || '');
}

sub resolve_callback_state {
    my $self = shift;
    my $args = shift || {};
    my $prefix = shift || 'auth_state';

    my $state = $args->{state};
    return $args unless $state;

    my $ctx = cache->get_json( $self->auth_state_cache_key( $state, $prefix ) );
    return $args unless ref $ctx eq 'HASH';

    $args->{expected_state} //= $ctx->{state};
    $args->{code_verifier} //= $ctx->{code_verifier};
    $args->{nonce} //= $ctx->{nonce};
    $args->{provider} //= $ctx->{provider};
    $args->{redirect_uri} //= $ctx->{redirect_uri};
    $args->{return_url} //= $ctx->{return_url} if defined $ctx->{return_url};
    $args->{register_if_not_exists} = $ctx->{register_if_not_exists}
        if !$args->{register_if_not_exists} && defined $ctx->{register_if_not_exists};
    $args->{bind_to_profile} = $ctx->{bind_to_profile}
        if !$args->{bind_to_profile} && defined $ctx->{bind_to_profile};
    $args->{bind_only_if_new} = $ctx->{bind_only_if_new}
        if !$args->{bind_only_if_new} && defined $ctx->{bind_only_if_new};
    $args->{session_id} //= $ctx->{session_id} if defined $ctx->{session_id};
    $args->{device_id} //= $ctx->{device_id} if defined $ctx->{device_id};

    cache->delete( $self->auth_state_cache_key( $state, $prefix ) );
    return $args;
}

sub build_callback_redirect_url {
    my $self = shift;
    my $result = shift;
    my $return_url = shift;
    my $default_error = shift || 'Authentication failed';
    my $status_key = shift || 'oidc_status';

    return undef unless $return_url;

    my %query;
    if ( ref $result eq 'HASH' && $result->{session_id} ) {
        %query = ( $status_key => 'success', session_id => $result->{session_id} );
    } elsif ( ref $result eq 'HASH' && ( $result->{error} || '' ) =~ /already linked/i ) {
        %query = ( $status_key => 'already_exists', error => $result->{error} );
    } elsif ( ref $result eq 'HASH' && ( $result->{error} || '' ) =~ /Already\s+bound/i ) {
        %query = ( $status_key => 'already_bound', error => $result->{error} );
    } elsif ( ref $result eq 'HASH' && ( $result->{msg} || '' ) =~ /Successfully\s+bound/i ) {
        %query = ( $status_key => 'success', msg => $result->{msg} );
    } elsif ( ref $result eq 'HASH' && $result->{error} ) {
        %query = ( $status_key => 'error', error => $result->{error} );
    } else {
        %query = ( $status_key => 'error', error => $default_error );
    }

    my $sep = ( $return_url =~ /\?/ ) ? '&' : '?';
    return $return_url . $sep . join('&', map { uri_escape($_) . '=' . uri_escape($query{$_}) } sort keys %query);
}

1;
