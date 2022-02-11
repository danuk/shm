use v5.14;
use utf8;

use Core::Utils qw/shm_test_api/;
use Test::More;

subtest 'Try to change user password' => sub {
    my %ret = shm_test_api(
        url => 'v1/user/passwd',
        method => 'POST',
        data => {
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
            password => 'danuk',
        },
        login => 'danuk',
        password => 'new_password',
    );

    is $ret{success}, 1;
};

done_testing();

exit 0;

