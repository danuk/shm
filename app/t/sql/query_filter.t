use v5.14;
use utf8;

use SHM;
use Test::More;
use Test::Deep;
use Core::Sql::Data qw/query_for_filtering/;
use Core::System::ServiceManager qw( get_service );

my $user = SHM->new( user_id => 40092 );

cmp_deeply (
    $user->query_for_filtering(
        user_id => 40092,
        full_name => "hello",
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
        alien => 'strange',
    ),
    {},
);

done_testing();
