package Core::Test;

use v5.14;
use parent 'Core::Base';
use Core::System::ServiceManager qw( %PROTECTED_SERVICES get_service logger );

sub list_for_api {
    my $self = shift;

    my $cache = get_service('Core::System::Cache');
    my %data;
    if ( $cache ) {
        %data = $cache->redis->hgetall('SHM:Cache:Reset');
    }

    return {
        test => 'OK',
        cache => {
            resets => \%data,
            objects => \%PROTECTED_SERVICES,
        },
    };
}

sub http_echo {
    my $self = shift;
    my %args = @_;

    return {
        payload => \%args,
        method => $ENV{REQUEST_METHOD},
    };
}

1;
