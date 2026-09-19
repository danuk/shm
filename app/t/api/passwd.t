use v5.14;
use utf8;

use Core::Utils qw/shm_test_api/;
use Test::More;

subtest 'Try to change user password' => sub {
    my %ret = shm_test_api(
        url => 'v1/user/passwd',
        method => 'POST',
        data => {
            old_password => 'danuk',
            password => 'new_password',
        },
        login => 'danuk',
        password => 'danuk',
    );

    is $ret{success}, 1;
};

subtest 'Try to auth with old password' => sub {
    my %ret = shm_test_api(
        url => 'v1/user/passwd',
        method => 'POST',
        data => {
            old_password => 'danuk',
            password => 'new_password',
        },
        login => 'danuk',
        password => 'danuk',
    );
    is $ret{success}, '';
};

subtest 'Set old password' => sub {
    my %ret = shm_test_api(
        url => 'v1/user/passwd',
        method => 'POST',
        data => {
            old_password => 'new_password',
            password => 'danuk',
        },
        login => 'danuk',
        password => 'new_password',
    );

    is $ret{success}, 1;
};

subtest 'Reject changing another login' => sub {
    my %ret = shm_test_api(
        url => 'v1/user/passwd',
        method => 'POST',
        data => {
            login => 'admin',
            old_password => 'new_password',
            password => 'should_not_work',
        },
        login => 'danuk',
        password => 'new_password',
    );

    is $ret{success}, '';
};

done_testing();

exit 0;
