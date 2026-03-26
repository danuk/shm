use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;

$ENV{SHM_TEST} = 1;
$ENV{DEBUG} = '';

use Core::System::ServiceManager qw( get_service );

my $http = get_service('Transport::Http');

subtest '' => sub {
    my $response = $http->http(url => 'http://api/404');
    like( $response->status_line, qr/404 Not Found/ );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://api');
    is( $response->code, 403 );
    like( $response->status_line, qr/403 Forbidden/ );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://api', method => 'GET');
    is( $response->is_success, '' );
    is( $response->code, 403 );
    like( $response->status_line, qr/403 Forbidden/ );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://api/shm/v1/test/http/echo', content => '{"test":"echo_post"}');
    is( $response->code, 200 );
    is( $response->json_content->{data}[0]->{payload}->{test}, 'echo_post' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://api/shm/v1/test/http/echo', content => { test => 'echo_post' } );
    is( $response->json_content->{data}[0]->{payload}->{test}, 'echo_post' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://api/shm/v1/test/http/echo?test3=test4', method => 'GET', content => 'test=echo_get&test1=test2');
    is( $response->json_content->{data}[0]->{payload}->{test}, 'echo_get' );
    is( $response->json_content->{data}[0]->{payload}->{test1}, 'test2' );
    is( $response->json_content->{data}[0]->{payload}->{test3}, 'test4' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://api/shm/v1/test/http/echo?format=json&test3=test4', method => 'GET', content => 'test=echo_get;test1=test2');
    is( $response->json_content->{payload}->{test}, 'echo_get' );
    is( $response->json_content->{payload}->{test1}, 'test2' );
    is( $response->json_content->{payload}->{test3}, 'test4' );
};

subtest '' => sub {
    my $response = $http->http(url => 'http://api/shm/v1/test/http/echo', method => 'POST', content_type => 'text/plain', content => 'hello world');
    is( $response->json_content->{data}[0]->{payload}->{POSTDATA}, 'hello world' );
};

subtest '' => sub {
    my $response = $http->post('http://api/shm/v1/test/http/echo', content_type => 'text/plain', content => 'hello world');
    is( $response->{data}[0]->{payload}->{POSTDATA}, 'hello world' );
    is( $response->{data}[0]->{method}, 'POST' );
};

subtest '' => sub {
    my $response = $http->delete('http://api/shm/v1/test/http/echo');
    is( $response->{status}, 200 );
    is( $response->{data}[0]->{method}, 'DELETE' );
};

done_testing();
