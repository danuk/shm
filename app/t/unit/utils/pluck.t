use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::Base;
use Core::Utils qw/pluck/;

subtest 'pluck from hashrefs by field key' => sub {
    my $res = pluck(
        [
            { login => 'a@example.com' },
            { login => 'b@example.com' },
        ],
        'login',
    );

    cmp_deeply( $res, [ 'a@example.com', 'b@example.com' ], 'extracts login from hashes' );
};

subtest 'pluck from hashrefs by getter key is not supported' => sub {
    my $res = pluck(
        [
            { login => 'a@example.com' },
            { login => 'b@example.com' },
        ],
        'get_login',
    );

    cmp_deeply( $res, [], 'getter-like key does not map to hash field names' );
};

subtest 'pluck from blessed objects by getter key' => sub {
    {
        package Test::PluckObj;
        sub new { bless { login => $_[1] }, $_[0] }
        sub get_login { $_[0]->{login} }
    }

    my $res = pluck(
        [
            Test::PluckObj->new('a@example.com'),
            Test::PluckObj->new('b@example.com'),
        ],
        'get_login',
    );

    cmp_deeply( $res, [ 'a@example.com', 'b@example.com' ], 'extracts via object getter method' );
};

subtest 'pluck from Base-like objects by field key' => sub {
    {
        package Test::PluckObj2;
        use parent -norequire, 'Core::Base';
        sub new { bless { res => { login => $_[1] } }, $_[0] }
    }

    my $res = pluck(
        [ Test::PluckObj2->new('a@example.com') ],
        'login',
    );

    cmp_deeply( $res, [ 'a@example.com' ], 'extracts login via Base AUTOLOAD when key is login' );
};

done_testing();
