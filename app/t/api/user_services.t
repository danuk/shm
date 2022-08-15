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

subtest 'GET /v1/user/service' => sub {
    my %ret = shm_test_api(
        url => 'v1/user/service',
        method => 'GET',
        %user,
    );
    is $ret{json}->{items}, 4, 'Check items field';
    is scalar @{ $ret{json}->{data} }, 4, 'Check count items in data';
};

subtest 'GET /v1/user/service' => sub {
    my %ret = shm_test_api(
        url => 'v1/user/service?usi=99',
        method => 'GET',
        %user,
    );
    is $ret{json}->{items}, 1, 'Check items field';
    is scalar @{ $ret{json}->{data} }, 1, 'Check count items in data';
    is $ret{json}->{data}->[0]->{user_service_id}, 99, 'Check user_service_id';
    is $ret{json}->{data}->[0]->{service_id}, 110, 'Check service_id';
};

done_testing();

exit 0;

