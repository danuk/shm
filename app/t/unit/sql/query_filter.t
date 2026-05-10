use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::Sql::Data qw/prepare_query_for_filtering/;

subtest 'prepare_query_for_filtering - isEmpty' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            name => \'isEmpty',
            email => \'isEmpty',
        }),
        {
            "--COALESCE(name, '')" => '',
            "--COALESCE(email, '')" => '',
        },
        'isEmpty converts to --COALESCE check for empty string'
    );
};

subtest 'prepare_query_for_filtering - isNotEmpty' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            name => \'isNotEmpty',
            description => \'isNotEmpty',
        }),
        {
            "--COALESCE(name, '')" => { '!=' => '' },
            "--COALESCE(description, '')" => { '!=' => '' },
        },
        'isNotEmpty converts to --COALESCE check for non-empty string'
    );
};

subtest 'prepare_query_for_filtering - null' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            role => \'null',
            manager_id => \'null',
        }),
        {
            role => undef,
            manager_id => undef,
        },
        'null converts to undef (which becomes IS NULL in SQL)'
    );
};

subtest 'prepare_query_for_filtering - isNull' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            role => \'isNull',
            manager_id => \'isNull',
            description => \'isNull',
        }),
        {
            role => undef,
            manager_id => undef,
            description => undef,
        },
        'isNull converts to undef (which becomes IS NULL in SQL)'
    );
};

subtest 'prepare_query_for_filtering - isNotNull' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            role => \'isNotNull',
            manager_id => \'isNotNull',
            email => \'isNotNull',
        }),
        {
            role => { '!=' => undef },
            manager_id => { '!=' => undef },
            email => { '!=' => undef },
        },
        'isNotNull converts to { "!=" => undef } (which becomes IS NOT NULL in SQL)'
    );
};

subtest 'prepare_query_for_filtering - true/false' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            active => \'true',
            deleted => \'false',
            verified => \'true',
        }),
        {
            active => 1,
            deleted => 0,
            verified => 1,
        },
        'true/false convert to 1/0'
    );
};

subtest 'prepare_query_for_filtering - numeric comparisons' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            age => \'lt:18',
            score => \'gt:100',
            rating => \'le:5',
            level => \'ge:10',
            user_id => \'eq:12345',
            status => \'ne:0',
        }),
        {
            age => { '<' => '18' },
            score => { '>' => '100' },
            rating => { '<=' => '5' },
            level => { '>=' => '10' },
            user_id => { '=' => '12345' },
            status => { '!=' => '0' },
        },
        'Numeric comparison operators work correctly'
    );
};

subtest 'prepare_query_for_filtering - between operator' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            age => \'between:18:65',
            score => \'between:0:100',
            price => \'between:10.5:99.99',
        }),
        {
            age => { '-between' => ['18', '65'] },
            score => { '-between' => ['0', '100'] },
            price => { '-between' => ['10.5', '99.99'] },
        },
        'BETWEEN operator works correctly'
    );
};

subtest 'prepare_query_for_filtering - sign checks' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            balance => \'isPositive',
            debt => \'isNegative',
            profit => \'isNonPositive',
            loss => \'isNonNegative',
        }),
        {
            balance => { '>' => 0 },
            debt => { '<' => 0 },
            profit => { '<=' => 0 },
            loss => { '>=' => 0 },
        },
        'Sign check operators (isPositive/isNegative) work correctly'
    );
};

subtest 'prepare_query_for_filtering - mixed values' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            name => \'isEmpty',
            email => \'isNotEmpty',
            role => \'null',
            manager_id => \'isNull',
            department => \'isNotNull',
            active => \'true',
            deleted => \'false',
            age => \'gt:18',
            score => \'between:80:100',
            balance => \'isPositive',
            debt => \'isNegative',
            regular_field => 'normal_value',
            hash_field => { '>' => 10 },
        }),
        {
            "--COALESCE(name, '')" => '',
            "--COALESCE(email, '')" => { '!=' => '' },
            role => undef,
            manager_id => undef,
            department => { '!=' => undef },
            active => 1,
            deleted => 0,
            age => { '>' => '18' },
            score => { '-between' => ['80', '100'] },
            balance => { '>' => 0 },
            debt => { '<' => 0 },
            regular_field => 'normal_value',
            hash_field => { '>' => 10 },
        },
        'Mixed special and regular values are processed correctly including sign checks'
    );
};

subtest 'prepare_query_for_filtering - edge cases' => sub {
    cmp_deeply(
        prepare_query_for_filtering({}),
        {},
        'Empty hash returns empty hash'
    );

    cmp_deeply(
        prepare_query_for_filtering('not a hash'),
        {},
        'Non-hash input returns empty hash'
    );

    cmp_deeply(
        prepare_query_for_filtering(undef),
        {},
        'undef input returns empty hash'
    );

    cmp_deeply(
        prepare_query_for_filtering({
            field => \'unknown_value',
        }),
        {
            field => \'unknown_value',
        },
        'Unknown scalar reference passed through unchanged'
    );
};

subtest 'prepare_query_for_filtering - nested JSON expressions' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            settings => {
                'auto_backup' => \'ne:1',
                'max_items' => \'gt:10',
                'notifications' => \'true',
                'theme' => 'dark',
            }
        }),
        {
            settings => {
                'auto_backup' => \'ne:1',
                'max_items' => \'gt:10',
                'notifications' => \'true',
                'theme' => 'dark',
            }
        },
        'prepare_query_for_filtering preserves nested JSON scalar references'
    );
};

subtest 'prepare_query_for_filtering - recursive logical groups' => sub {
    cmp_deeply(
        prepare_query_for_filtering({
            status => 1,
            '-or' => {
                balance => \'gt:1000',
                settings => {
                    vip => \'true',
                },
            },
            '-and' => {
                block => \'false',
            },
        }),
        {
            status => 1,
            '-or' => {
                balance => { '>' => '1000' },
                settings => {
                    vip => \'true',
                },
            },
            '-and' => {
                block => 0,
            },
        },
        'Logical groups are prepared recursively and keep nested JSON hash payloads'
    );
};

subtest 'query_for_filtering - nested JSON expressions with mock' => sub {
    my $test_obj = bless {}, 'TestJSONClass';

    no warnings 'redefine';
    local *TestJSONClass::can = sub {
        my ($self, $method) = @_;
        return 1 if $method eq 'structure';
        return 0;
    };
    local *TestJSONClass::structure = sub {
        return {
            settings => { type => 'json' },
            user_id => { type => 'number', key => 1 },
        };
    };

    @TestJSONClass::ISA = ('Core::Sql::Data');

    my $result = $test_obj->query_for_filtering(
        user_id => 123,
        settings => {
            'auto_backup' => \'ne:1',
            'max_items' => \'gt:10',
            'notifications' => \'true',
            'theme' => 'dark',
            'priority' => \'le:5',
            'enabled' => \'false',
            'api_key' => \'isNotNull',
            'temp_data' => \'isEmpty',
        }
    );

    is($result->{user_id}, 123, 'Regular field passed through');
    cmp_deeply($result->{"settings->>'\$.auto_backup'"}, { '!=' => '1' }, 'ne:1 converted correctly for JSON field');
    cmp_deeply($result->{"settings->>'\$.max_items'"}, { '>' => '10' }, 'gt:10 converted correctly for JSON field');
    cmp_deeply($result->{"settings->>'\$.priority'"}, { '<=' => '5' }, 'le:5 converted correctly for JSON field');
    is($result->{"settings->>'\$.notifications'"}, 1, 'true converted to 1 for JSON field');
    is($result->{"settings->>'\$.enabled'"}, 0, 'false converted to 0 for JSON field');
    is($result->{"settings->>'\$.theme'"}, 'dark', 'Regular string value preserved for JSON field');
    cmp_deeply($result->{"settings->>'\$.api_key'"}, { '!=' => undef }, 'isNotNull converted correctly for JSON field');
    ok(exists $result->{"COALESCE(settings->>'\$.temp_data', '')"}, 'COALESCE field exists for isEmpty in JSON');
    is($result->{"COALESCE(settings->>'\$.temp_data', '')"}, '', 'isEmpty converted correctly for JSON field');
};

subtest '--COALESCE keys handling in query_for_filtering with mock' => sub {
    my $test_obj = bless {}, 'TestClass';

    no warnings 'redefine';
    local *TestClass::can = sub {
        my ($self, $method) = @_;
        return 1 if $method eq 'structure';
        return 0;
    };
    local *TestClass::structure = sub {
        return {
            full_name => { type => 'text' },
            email => { type => 'text' },
            user_id => { type => 'number', key => 1 },
        };
    };

    @TestClass::ISA = ('Core::Sql::Data');

    my $result = $test_obj->query_for_filtering(
        full_name => \'isEmpty',
        email => \'isNotEmpty',
        user_id => 123,
    );

    ok(exists $result->{"COALESCE(full_name, '')"}, 'COALESCE key for full_name exists (-- prefix removed)');
    ok(exists $result->{"COALESCE(email, '')"}, 'COALESCE key for email exists (-- prefix removed)');
    is($result->{"COALESCE(full_name, '')"}, '', 'isEmpty converts to empty string');
    cmp_deeply($result->{"COALESCE(email, '')"}, { '!=' => '' }, 'isNotEmpty converts correctly');
    is($result->{user_id}, 123, 'Regular field passed through');
};

subtest 'query_for_filtering with mock user object' => sub {
    {
        package MockSHMUser;
        use parent -norequire, 'Core::Sql::Data';
        sub table { 'users' }
        sub structure {
            return {
                user_id   => { type => 'number', key => 1 },
                full_name => { type => 'text' },
                settings  => { type => 'json' },
            };
        }
    }

    my $user = bless {}, 'MockSHMUser';

    cmp_deeply(
        $user->query_for_filtering(
            user_id   => 40092,
            full_name => "%hello%",
            alien     => 'strange',
        ),
        {
            user_id   => 40092,
            full_name => { '-like' => '%hello%' },
        },
        'alien field filtered out, full_name gets -like',
    );

    cmp_deeply(
        $user->query_for_filtering(
            user_id   => 40092,
            full_name => { -not_like => "%hello%" },
        ),
        {
            user_id   => 40092,
            full_name => { '-not_like' => '%hello%' },
        },
        '-not_like passed through unchanged',
    );

    cmp_deeply(
        $user->query_for_filtering(
            user_id  => 40092,
            settings => 'a.b',
        ),
        {
            user_id                       => 40092,
            q/JSON_EXTRACT(settings, '$.a.b')/ => { '!=' => undef },
        },
        'JSON path existence check (a.b)',
    );

    cmp_deeply(
        $user->query_for_filtering(
            user_id  => 40092,
            settings => '!a.b',
        ),
        {
            user_id                       => 40092,
            q/JSON_EXTRACT(settings, '$.a.b')/ => { '=' => undef },
        },
        'JSON path non-existence check (!a.b)',
    );

    cmp_deeply(
        $user->query_for_filtering(
            user_id  => 40092,
            settings => { 'a.b' => 1, 'c' => { '>' => 2 } },
        ),
        {
            user_id              => 40092,
            q/settings->>'$.a.b'/ => 1,
            q/settings->>'$.c'/   => { '>' => 2 },
        },
        'JSON value comparisons (a.b and c)',
    );

    cmp_deeply(
        $user->query_for_filtering( alien => 'strange' ),
        {},
        'only unknown fields returns empty hash',
    );

    my $result = $user->query_for_filtering(
        user_id   => 40092,
        full_name => \'isEmpty',
        email     => \'isNotEmpty',
        role      => \'null',
        active    => \'true',
    );
    is( $result->{user_id}, 40092, 'user_id preserved when mixed with special-value fields' );
};

subtest 'query_for_filtering - OR with scalar refs and JSON values' => sub {
    {
        package MockFilterUser;
        use parent -norequire, 'Core::Sql::Data';
        sub table { 'users' }
        sub structure {
            return {
                user_id  => { type => 'number', key => 1 },
                status   => { type => 'number' },
                block    => { type => 'number' },
                balance  => { type => 'number' },
                settings => { type => 'json' },
            };
        }
    }

    my $user = bless {}, 'MockFilterUser';

    my $where = $user->query_for_filtering(
        status => 1,
        block  => 0,
        '-or'  => {
            balance  => \'gt:1000',
            settings => { vip => \'true' },
        },
    );

    is( $where->{status}, 1, 'status condition preserved' );
    is( $where->{block}, 0, 'block condition preserved' );
    cmp_deeply(
        $where->{'-or'},
        [
            { balance => { '>' => '1000' } },
            { q/settings->>'$.vip'/ => 1 },
        ],
        'OR group is converted into SQL::Abstract compatible conditions',
    );
};

subtest 'Template functions integration' => sub {
    my $lt = sub { return \('lt:' . ($_[0] // '')) };
    my $gt = sub { return \('gt:' . ($_[0] // '')) };
    my $between = sub {
        my ($min, $max) = @_;
        return \("between:$min:$max") if defined $min && defined $max;
        return \'between';
    };
    my $isEmpty = sub { return \'isEmpty' };
    my $isPositive = sub { return \'isPositive' };
    my $isNegative = sub { return \'isNegative' };

    my $lt_result = $lt->(18);
    my $gt_result = $gt->(100);
    my $between_result = $between->(10, 50);
    my $isEmpty_result = $isEmpty->();
    my $isPositive_result = $isPositive->();
    my $isNegative_result = $isNegative->();

    is(ref $lt_result, 'SCALAR', 'lt() returns scalar reference');
    is($$lt_result, 'lt:18', 'lt() contains correct value');
    is(ref $gt_result, 'SCALAR', 'gt() returns scalar reference');
    is($$gt_result, 'gt:100', 'gt() contains correct value');
    is(ref $between_result, 'SCALAR', 'between() returns scalar reference');
    is($$between_result, 'between:10:50', 'between() contains correct value');
    is(ref $isEmpty_result, 'SCALAR', 'isEmpty() returns scalar reference');
    is($$isEmpty_result, 'isEmpty', 'isEmpty() contains correct value');
    is(ref $isPositive_result, 'SCALAR', 'isPositive() returns scalar reference');
    is($$isPositive_result, 'isPositive', 'isPositive() contains correct value');
    is(ref $isNegative_result, 'SCALAR', 'isNegative() returns scalar reference');
    is($$isNegative_result, 'isNegative', 'isNegative() contains correct value');

    my $processed = prepare_query_for_filtering({
        age => $lt_result,
        score => $gt_result,
        rating => $between_result,
        name => $isEmpty_result,
        balance => $isPositive_result,
        debt => $isNegative_result,
    });

    cmp_deeply(
        $processed,
        {
            age => { '<' => '18' },
            score => { '>' => '100' },
            rating => { '-between' => ['10', '50'] },
            "--COALESCE(name, '')" => '',
            balance => { '>' => 0 },
            debt => { '<' => 0 },
        },
        'Template functions including sign checks integrate correctly with prepare_query_for_filtering'
    );
};

done_testing();
