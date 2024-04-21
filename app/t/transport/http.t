use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );

my $http = get_service('Transport::Http');

subtest '' => sub {
    my $response = $http->http(url => 'http://admin/404');
    like( $response->status_line, qr/404 Not Found/ );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://admin');
    is( $response->code, 405 );
    like( $response->status_line, qr/405 Not Allowed/ );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://admin', method => 'GET');
    is( $response->is_success, 1 );
    is( $response->status_line, '200 OK' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://admin/shm/v1/test/http/echo', content => '{"test":"echo_post"}');
    is( $response->code, 200 );
    is( $response->json_content->{data}[0]->{payload}->{test}, 'echo_post' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://admin/shm/v1/test/http/echo', content => { test => 'echo_post' } );
    is( $response->json_content->{data}[0]->{payload}->{test}, 'echo_post' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://admin/shm/v1/test/http/echo?test3=test4', method => 'GET', content => 'test=echo_get&test1=test2');
    is( $response->json_content->{data}[0]->{payload}->{test}, 'echo_get' );
    is( $response->json_content->{data}[0]->{payload}->{test1}, 'test2' );
    is( $response->json_content->{data}[0]->{payload}->{test3}, 'test4' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://admin/shm/v1/test/http/echo?format=json&test3=test4', method => 'GET', content => 'test=echo_get;test1=test2');
    is( $response->json_content->{payload}->{test}, 'echo_get' );
    is( $response->json_content->{payload}->{test1}, 'test2' );
    is( $response->json_content->{payload}->{test3}, 'test4' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://admin/shm/v1/test/http/echo', method => 'POST', content_type => 'text/plain', content => 'hello world');
    is( $response->json_content->{data}[0]->{payload}->{POSTDATA}, 'hello world' );
};

done_testing();
