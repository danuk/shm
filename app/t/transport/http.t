use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );

my $http = get_service('Transport::Http');

my $nf = $http->send_req(url => 'https://docs.myshm.ru/404');
is( $nf->{message}, undef );
like( $nf->{error}, qr/404 Not Found/ );

my $na = $http->send_req(url => 'https://docs.myshm.ru/');
is( $na->{message}, undef );
like( $na->{error}, qr/405 Not Allowed/ );

my $ok = $http->send_req(url => 'https://docs.myshm.ru/', method => 'GET');
is( $ok->{message}, 'successful' );
is( $ok->{error}, undef );

done_testing();
