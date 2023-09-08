use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );

my $http = get_service('Transport::Http');

my $nf = $http->http(url => 'http://admin/404');
is( $nf->{message}, undef );
like( $nf->{error}, qr/404 Not Found/ );

my $na = $http->http(url => 'http://admin');
is( $na->{message}, undef );
like( $na->{error}, qr/405 Not Allowed/ );

my $ok = $http->http(url => 'http://admin', method => 'GET');
is( $ok->{message}, 'successful' );
is( $ok->{error}, undef );

my $post = $http->http(url => 'http://admin/shm/v1/test/http/echo', content => '{"test":"echo_post"}');
is( $post->{message}, 'successful' );
is( $post->{error}, undef );
is( $post->{response}->{data}[0]->{payload}->{test}, 'echo_post' );

my $get = $http->http(url => 'http://admin/shm/v1/test/http/echo?test3=test4', method => 'GET', content => 'test=echo_get&test1=test2');
is( $get->{message}, 'successful' );
is( $get->{error}, undef );
is( $get->{response}->{data}[0]->{payload}->{test}, 'echo_get' );
is( $get->{response}->{data}[0]->{payload}->{test1}, 'test2' );
is( $get->{response}->{data}[0]->{payload}->{test3}, 'test4' );

my $get = $http->http(url => 'http://admin/shm/v1/test/http/echo?test3=test4', method => 'GET', content => 'test=echo_get;test1=test2');
is( $get->{message}, 'successful' );
is( $get->{error}, undef );
is( $get->{response}->{data}[0]->{payload}->{test}, 'echo_get' );
is( $get->{response}->{data}[0]->{payload}->{test1}, 'test2' );
is( $get->{response}->{data}[0]->{payload}->{test3}, 'test4' );

done_testing();
