use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );

my $http = get_service('Transport::Http');

subtest '' => sub {
    my ( $response, $content ) = $http->http(url => 'http://admin/404');
    like( $response->status_line, qr/404 Not Found/ );
};

subtest '' => sub {
    my ( $response, $content ) = $http->http(url => 'http://admin');
    like( $response->status_line, qr/405 Not Allowed/ );
};

subtest '' => sub {
    my ( $response, $content ) = $http->http(url => 'http://admin', method => 'GET');
    is( $response->is_success, 1 );
    is( $response->{status_line}, undef );
};

subtest '' => sub {
    my ( $response, $content ) = $http->http(url => 'http://admin/shm/v1/test/http/echo', content => '{"test":"echo_post"}');
    is( $response->{status_line}, undef );
    is( $content->{data}[0]->{payload}->{test}, 'echo_post' );
};

subtest '' => sub {
    my ( $response, $content ) = $http->http(url => 'http://admin/shm/v1/test/http/echo', content => { test => 'echo_post' } );
    is( $content->{data}[0]->{payload}->{test}, 'echo_post' );
};

subtest '' => sub {
    my ( $response, $content ) = $http->http(url => 'http://admin/shm/v1/test/http/echo?test3=test4', method => 'GET', content => 'test=echo_get&test1=test2');
    is( $content->{data}[0]->{payload}->{test}, 'echo_get' );
    is( $content->{data}[0]->{payload}->{test1}, 'test2' );
    is( $content->{data}[0]->{payload}->{test3}, 'test4' );
};

subtest '' => sub {
    my ( $response, $content ) = $http->http(url => 'http://admin/shm/v1/test/http/echo?format=json&test3=test4', method => 'GET', content => 'test=echo_get;test1=test2');
    is( $content->{payload}->{test}, 'echo_get' );
    is( $content->{payload}->{test1}, 'test2' );
    is( $content->{payload}->{test3}, 'test4' );
};

done_testing();
