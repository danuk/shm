use v5.14;
use utf8;

use Test::More;
use Core::Sql::Data qw/query_select/;
use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

my @vars;

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
), "SELECT * FROM domains";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
    calc => 1,
), "SELECT SQL_CALC_FOUND_ROWS * FROM domains";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
    fields => 'id,date',
), "SELECT id,date FROM domains";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
), "SELECT * FROM domains";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
    range => { field => 'date', start => '2016-11-12', stop => '2016-12-31' },
), "SELECT * FROM domains WHERE ( ( date BETWEEN ? AND ? ) )";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
    range => { field => 'date', start => '2016-11-12' },
), "SELECT * FROM domains WHERE ( date >= ? )";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
    range => { field => 'date', stop => '2016-12-31' },
), "SELECT * FROM domains WHERE ( date <= ? )";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
    limit => 5,
), "SELECT * FROM domains LIMIT ?";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
    limit => 5,
    offset => 7,
), "SELECT * FROM domains LIMIT ? OFFSET ?";

is query_select(
    undef,
    vars => \@vars,
    table => 'domains',
    limit => '',
    offset => 7,
), "SELECT * FROM domains";

is query_select(
    undef,
    vars => \@vars,
    table => 'user_services',
    join => { table => 'services', using => ['service_id'] },
), "SELECT * FROM user_services JOIN services USING(service_id)";

is query_select(
    undef,
    vars => \@vars,
    table => 'user_services',
    join => { table => 'services', using => ['service_id'], dir => 'RIGHT' },
), "SELECT * FROM user_services RIGHT JOIN services USING(service_id)";

is query_select(
    undef,
    vars => \@vars,
    table => 'user_services',
    join => { table => 'services', using => ['id','service_id'], dir => 'LEFT' },
), "SELECT * FROM user_services LEFT JOIN services USING(id,service_id)";

is query_select(
    undef,
    vars => \@vars,
    table => 'user_services',
    join => { table => 'services', on => ['id','service_id'] },
), "SELECT * FROM user_services JOIN services ON user_services.id=services.service_id";

is query_select(
    undef,
    vars => \@vars,
    table => 'user_services',
    order => [ a => 'desc', b => 'asc' ],
), "SELECT * FROM user_services ORDER BY `a` desc,`b` asc";

is query_select(
    undef,
    vars => \@vars,
    table => 'test',
    where => { -and => [ { user_id => 1 }, { b => 2, c => 3 } ] },
), "SELECT * FROM test WHERE ( ( user_id = ? AND ( b = ? AND c = ? ) ) )";

is query_select(
    undef,
    vars => \@vars,
    table => 'test',
    user_id => 123,
    where => { -or => [ { user_service_id => { -in => [1,2] } },
        { parent => { '!=' => undef } },
    ]},
), "SELECT * FROM test WHERE ( ( user_id = ? AND ( user_service_id IN ( ?, ? ) OR parent IS NOT NULL ) ) )";

is query_select(
    undef,
    vars => \@vars,
    table => 'test',
    user_id => 123,
    where => { 'table.field' => 1 },
), "SELECT * FROM test WHERE ( ( user_id = ? AND table.field = ? ) )";

is $user->query_select(
    vars => \@vars,
    user_id => 123,
    where => {
        'settings.cmd' => 1,
    },
), q/SELECT * FROM users WHERE ( ( user_id = ? AND settings->>"$.cmd" = ? ) )/;

is $user->query_select(
    vars => \@vars,
    user_id => 123,
    where => {
        'settings.cmd.test' => 1,
    },
), q/SELECT * FROM users WHERE ( ( user_id = ? AND settings->>"$.cmd.test" = ? ) )/;

done_testing();
