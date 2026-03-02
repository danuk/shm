use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::Sql::Data qw/query_for_order/;

{
    package MockSHMUser;
    use parent -norequire, 'Core::Sql::Data';
    sub table { 'users' }
    sub structure {
        return {
            user_id   => { type => 'number', key => 1 },
            full_name => { type => 'text' },
            created   => { type => 'date' },
        };
    }
}

my $user = bless {}, 'MockSHMUser';

cmp_deeply(
    $user->query_for_order(
        sort_field     => 'user_id',
        sort_direction => 'asc',
    ),
    [ 'user_id' => 'asc' ],
    'known field with explicit direction',
);

cmp_deeply(
    $user->query_for_order(
        sort_field => 'created',
    ),
    [ 'created' => 'desc' ],
    'known field defaults to desc',
);

cmp_deeply(
    $user->query_for_order(
        sort_field     => 'alien',
        sort_direction => 'asc',
    ),
    [ 'user_id' => 'asc' ],
    'unknown field falls back to primary key',
);

done_testing();
