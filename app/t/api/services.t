use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Utils qw/shm_test_api/;

my %user = (
    login => 'danuk',
    password => 'danuk',
);

subtest 'GET /v1/service/' => sub {
    my %ret = shm_test_api(
        url => 'v1/service?service_id=5',
        method => 'GET',
        %user,
    );
    is $ret{json}->{items}, 1, 'Check items field';
    is scalar @{ $ret{json}->{data} }, 1, 'Check count items in data';
    is $ret{json}->{data}->[0]->{service_id}, 5, 'Check data';
};

done_testing();

exit 0;

