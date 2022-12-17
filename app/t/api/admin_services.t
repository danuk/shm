use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::Utils qw/shm_test_api/;

my %user = (
    login => 'admin',
    password => 'admin',
);

subtest 'GET /v1/admin/service' => sub {
    my %ret = shm_test_api(
        url => 'v1/admin/service',
        method => 'GET',
        %user,
    );
    is $ret{json}->{items}, 15, 'Check items field';
    is scalar @{ $ret{json}->{data} }, 15, 'Check count items in data';
};

subtest 'GET /v1/admin/service/110' => sub {
    my %ret = shm_test_api(
        url => 'v1/admin/service?service_id=110',
        method => 'GET',
        %user,
    );
    is $ret{json}->{items}, 1, 'Check items field';
    is scalar @{ $ret{json}->{data} }, 1, 'Check count items in data';
    is $ret{json}->{data}->[0]->{service_id}, 110, 'Check service data';
    is $ret{json}->{data}->[0]->{cost}, 300, 'Check service cost';
};

subtest 'POST /v1/admin/service/110' => sub {
    my %ret = shm_test_api(
        url => 'v1/admin/service',
        method => 'POST',
        data => {
            service_id => 110,
            cost => 400,
        },
        %user,
    );
    is $ret{json}->{data}->[0]->{cost}, 400, 'Check service cost (POST)';

    %ret = shm_test_api(
        url => 'v1/admin/service?service_id=110',
        method => 'GET',
        %user,
    );
    is $ret{json}->{data}->[0]->{cost}, 400, 'Check service cost (GET)';

    %ret = shm_test_api(
        url => 'v1/admin/service',
        method => 'POST',
        data => {
            service_id => 110,
            cost => 300,
        },
        %user,
    );
    is $ret{json}->{data}->[0]->{cost}, 300, 'Rollback service cost';
};

subtest 'PUT /v1/admin/service' => sub {
    my %ret = shm_test_api(
        url => 'v1/admin/service',
        method => 'PUT',
        data => {
            service_id => 1000,
            name => 'test 1',
            category => 'test',
            cost => 123,
        },
        %user,
    );
    is $ret{json}->{data}->[0]->{cost}, 123, 'Check new service cost';
    is $ret{json}->{data}->[0]->{service_id}, 1000, 'Check new service id';

    %ret = shm_test_api(
        url => 'v1/admin/service?service_id=1000',
        method => 'GET',
        %user,
    );
    is $ret{json}->{data}->[0]->{cost}, 123, 'Check new service cost (GET)';

    my %ret = shm_test_api(
        url => 'v1/admin/service',
        method => 'PUT',
        data => {
            service_id => 1000,
            name => 'test 1',
            category => 'test',
            cost => 123,
        },
        %user,
    );
    is $ret{json}->{error}, "Duplicate entry '1000' for key 'services.PRIMARY'";
};

subtest 'DELETE /v1/admin/service' => sub {
    my %ret = shm_test_api(
        url => 'v1/admin/service?service_id=1000',
        method => 'DELETE',
        %user,
    );
    is scalar @{ $ret{json}->{data} }, 0;

    %ret = shm_test_api(
        url => 'v1/admin/service?service_id=1000',
        method => 'DELETE',
        %user,
    );
    is scalar $ret{json}->{error}, "Service not found";
};

done_testing();

exit 0;

