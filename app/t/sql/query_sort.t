use v5.14;
use utf8;

use SHM;
use Test::More;
use Test::Deep;
use Core::Sql::Data qw/query_for_order/;

my $user = SHM->new( user_id => 40092 );

cmp_deeply (
    $user->query_for_order(
        sort_field => 'user_id',
        sort_direction => 'asc',
    ),
    [ 'user_id' => 'asc' ]
);

cmp_deeply (
    $user->query_for_order(
        sort_field => 'created',
    ),
    [ 'created' => 'desc' ]
);

cmp_deeply (
    $user->query_for_order(
        sort_field => 'alien',
        sort_direction => 'asc',
    ),
    [ 'user_id' => 'asc' ]
);

done_testing();
