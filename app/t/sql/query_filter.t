use v5.14;
use utf8;

use SHM;
use Test::More;
use Test::Deep;
use Core::Sql::Data qw/query_for_filtering/;
use Core::System::ServiceManager qw( get_service );
use Data::Dumper;

my $user = SHM->new( user_id => 40092 );

cmp_deeply (
    $user->query_for_filtering(
        user_id => 40092,
        full_name => "%hello%",
        alien => 'strange',
    ),
    {
        'user_id' => 40092,
        'full_name' => {
            '-like' => '%hello%'
        }
    },
);

cmp_deeply (
    $user->query_for_filtering(
        user_id => 40092,
        full_name => { -not_like => "%hello%" },
    ),
    {
        'user_id' => 40092,
        'full_name' => {
            '-not_like' => '%hello%'
        }
    },
);

cmp_deeply (
    $user->query_for_filtering(
        user_id => 40092,
        settings => 'a.b',
    ),
    {
        user_id => 40092,
        q/JSON_EXTRACT(settings, '$.a.b')/ => { '!=', undef },
    },
    'Check exits a->b in settings'
);

cmp_deeply (
    $user->query_for_filtering(
        user_id => 40092,
        settings => '!a.b',
    ),
    {
        user_id => 40092,
        q/JSON_EXTRACT(settings, '$.a.b')/ => { '=', undef },
    },
    'Check non exits a->b in settings'
);

cmp_deeply (
    $user->query_for_filtering(
        user_id => 40092,
        settings => { 'a.b' => 1, 'c' => { '>', 2 } },
    ),
    {
        user_id => 40092,
        q/settings->>'$.a.b'/ => 1,
        q/settings->>'$.c'/ => { '>', 2 },
    },
    'Check values for a->b and c in settings'
);

cmp_deeply (
    $user->query_for_filtering(
        alien => 'strange',
    ),
    {},
);

done_testing();
