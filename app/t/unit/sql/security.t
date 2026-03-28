use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::Sql::Data qw/prepare_query_for_filtering is_safe_identifier/;
use Core::Utils qw/dots_str_to_sql/;

# ---------------------------------------------------------------------------
# Mock object for methods that require $self with a structure
# ---------------------------------------------------------------------------
{
    package MockTable;
    use parent -norequire, 'Core::Sql::Data';
    sub table { 'users' }
    sub structure {
        return {
            user_id  => { type => 'number', key => 1 },
            name     => { type => 'text' },
            balance  => { type => 'number' },
            settings => { type => 'json', value => {} },
            created  => { type => 'now' },
        };
    }
}

my $obj = bless {}, 'MockTable';

# ===========================================================================
# 1. prepare_query_for_filtering: -- prefix injection
# ===========================================================================
subtest 'prepare_query_for_filtering - rejects -- prefix keys' => sub {
    my $result = prepare_query_for_filtering({
        '--1=1 OR 1'    => '1',
        '--DROP TABLE'  => 'x',
        name            => 'Alice',
    });

    ok( !exists $result->{'--1=1 OR 1'},   '-- injection key is stripped' );
    ok( !exists $result->{'--DROP TABLE'}, '-- DROP TABLE key is stripped' );
    is( $result->{name}, 'Alice',          'normal key passes through' );
};

# ===========================================================================
# 2. prepare_query_for_filtering: isEmpty/isNotEmpty only on safe identifiers
# ===========================================================================
subtest 'prepare_query_for_filtering - isEmpty/isNotEmpty reject unsafe field names' => sub {
    my $inject = '1=1) OR (1';

    my $result = prepare_query_for_filtering({
        $inject => \'isEmpty',
    });

    ok( !exists $result->{"--COALESCE($inject, '')"},
        'isEmpty with injected field name is rejected' );
    is( scalar keys %$result, 0, 'result is empty' );

    $result = prepare_query_for_filtering({
        $inject => \'isNotEmpty',
    });
    ok( !exists $result->{"--COALESCE($inject, '')"},
        'isNotEmpty with injected field name is rejected' );
};

subtest 'prepare_query_for_filtering - isEmpty/isNotEmpty accept safe identifiers' => sub {
    cmp_deeply(
        prepare_query_for_filtering({ name => \'isEmpty' }),
        { "--COALESCE(name, '')" => '' },
        'safe identifier passes isEmpty',
    );
    cmp_deeply(
        prepare_query_for_filtering({ name => \'isNotEmpty' }),
        { "--COALESCE(name, '')" => { '!=' => '' } },
        'safe identifier passes isNotEmpty',
    );
};

# ===========================================================================
# 3. is_safe_identifier
# ===========================================================================
subtest 'is_safe_identifier - valid identifiers' => sub {
    ok( is_safe_identifier('name'),           'simple name' );
    ok( is_safe_identifier('user_id'),        'underscore' );
    ok( is_safe_identifier('CamelCase'),      'mixed case' );
    ok( is_safe_identifier('a'),              'single char' );
    ok( is_safe_identifier('a.b', allow_dots => 1),  'dotted path with allow_dots' );
    ok( is_safe_identifier('a.b.c', allow_dots => 1), 'deep dotted path' );
};

subtest 'is_safe_identifier - invalid identifiers' => sub {
    ok( !is_safe_identifier("1name"),         'starts with digit' );
    ok( !is_safe_identifier("na me"),         'contains space' );
    ok( !is_safe_identifier("na'me"),         'contains quote' );
    ok( !is_safe_identifier('a;DROP TABLE'),  'SQL injection attempt' );
    ok( !is_safe_identifier('a.b'),           'dot without allow_dots' );
    ok( !is_safe_identifier('a.b.c'),         'deep dot without allow_dots' );
    ok( !is_safe_identifier(''),              'empty string' );
    ok( !is_safe_identifier("a\x00b"),        'null byte' );
};

# ===========================================================================
# 4. dots_str_to_sql: rejects unsafe segments
# ===========================================================================
subtest 'dots_str_to_sql - rejects injected subkeys' => sub {
    my $safe = dots_str_to_sql("settings.valid_key");
    ok( defined $safe, 'safe dotted key returns result' );
    is( $safe->{field}, 'settings', 'field part is correct' );
    like( $safe->{query}, qr/valid_key/, 'query contains subkey' );

    ok( !defined dots_str_to_sql("settings.x' OR 1=1"),   'SQL injection in subkey is rejected' );
    ok( !defined dots_str_to_sql("settings.a;DROP TABLE"), 'semicolon in subkey is rejected' );
    ok( !defined dots_str_to_sql("1invalid.key"),          'invalid field name is rejected' );
    ok( !defined dots_str_to_sql("settings.key space"),    'space in subkey is rejected' );
};

subtest 'dots_str_to_sql - accepts valid dotted paths' => sub {
    my $r = dots_str_to_sql("settings.server_id");
    ok( defined $r, 'valid path returns result' );
    is( $r->{field}, 'settings' );
    is( $r->{name},  'settings_server_id' );
    like( $r->{query}, qr/\$\.server_id/, 'JSON path is correct' );

    ok( defined dots_str_to_sql("data.foo.bar"), 'nested dotted path is accepted' );
};

# ===========================================================================
# 5. query_for_filtering: -- prefix keys do NOT reach %where
# ===========================================================================
subtest 'query_for_filtering - -- keys from filter do not reach WHERE' => sub {
    my $where = $obj->query_for_filtering(
        '--1=1 OR 1' => '1',
        name         => 'Alice%',
    );

    ok( !exists $where->{'1=1 OR 1'}, '-- injection key stripped before reaching WHERE' );
    ok( exists $where->{name},        'normal key still present in WHERE' );
};

# ===========================================================================
# 6. query_for_filtering: JSON subkey injection via HASH value
# ===========================================================================
subtest 'query_for_filtering - JSON subkey injection rejected' => sub {
    my $where = $obj->query_for_filtering(
        settings => { "x' OR 1=1" => 'val' },
    );

    my @keys = keys %$where;
    ok( !grep { /OR 1=1/ } @keys, 'injected JSON subkey does not appear in WHERE' );
};

subtest 'query_for_filtering - valid JSON subkey accepted' => sub {
    my $where = $obj->query_for_filtering(
        settings => { server_id => 42 },
    );

    my @keys = keys %$where;
    ok( grep { /server_id/ } @keys, 'valid JSON subkey appears in WHERE' );
};

# ===========================================================================
# 7. sort_direction validation
# ===========================================================================
subtest 'query_for_order - sort_direction validation' => sub {
    ok( !defined $obj->query_for_order( sort_field => 'name', sort_direction => 'invalid' ),
        'invalid direction returns undef' );
    ok( !defined $obj->query_for_order( sort_field => 'name', sort_direction => '1;DROP TABLE' ),
        'injected direction returns undef' );
    ok( defined $obj->query_for_order( sort_field => 'name', sort_direction => 'ASC' ),
        'ASC is accepted' );
    ok( defined $obj->query_for_order( sort_field => 'name', sort_direction => 'desc' ),
        'desc (lowercase) is accepted' );
};

done_testing();
