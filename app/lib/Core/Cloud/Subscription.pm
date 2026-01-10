package Core::Cloud::Subscription;

use v5.14;
use parent 'Core::Cloud';
use Core::Base;
use Core::Utils qw(
    encode_json
    decode_json
    now
);

sub _subscription_cache_file {
    my $self = shift;
    return '/tmp/shm_subscription_cache.json';
}

sub clear_subscription_cache {
    my $self = shift;
    my $cache_file = $self->_subscription_cache_file();
    unlink $cache_file if -f $cache_file;
    return 1;
}

sub check_subscription {
    my $self = shift;
    my $cache_file = $self->_subscription_cache_file();
    my $current_time = now();

    return 0 unless $self->get_auth_basic();

    # Try to read from cache file first
    if (-f $cache_file) {
        if (open my $fh, '<', $cache_file) {
            local $/;
            my $content = <$fh>;
            close $fh;

            if (my $cache_data = decode_json($content)) {
                my $expire_date = $cache_data->{expire} || '';
                if ($expire_date gt $current_time) {
                    return 1; # Subscription is valid from cache
                }
            }
        }
    }

    # Cache miss or expired, check via API
    my $response = $self->cloud_request(
        url => '/service/sub/get',
        method => 'get',
    );

    unless ($response && $response->is_success) {
        return 0; # Failed to check subscription
    }

    my $data = decode_json($response->decoded_content);
    unless ($data && $data->{expire}) {
        return 0; # No expire field in response
    }

    my $expire_date = $data->{expire};
    if ($expire_date gt $current_time) {
        # Save to cache file
        if (open my $fh, '>', $cache_file) {
            print $fh encode_json({ expire => $expire_date });
            close $fh;
        }
        return 1; # Subscription is valid
    }

    return 0; # Subscription expired
}

1;