use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::USObject;

# Minimal mock object — structure() is inherited from Core::USObject
my $obj = bless {}, 'Core::USObject';

# Helper: call list_for_api and capture the args passed to the parent
sub call_and_capture {
    my @call_args = @_;
    my %captured;
    no warnings 'redefine';
    local *Core::Sql::Data::list_for_api = sub {
        my $self = shift;
        %captured = @_;
        return ();
    };
    $obj->list_for_api( @call_args );
    return %captured;
}

# ---------------------------------------------------------------------------
# 1. fields is always overridden to the internal JOIN expression
# ---------------------------------------------------------------------------
subtest 'list_for_api - fields contains required SQL fragments' => sub {
    my %got = call_and_capture();

    like( $got{fields}, qr/user_services\.\*/,
        'fields includes user_services.*' );
    like( $got{fields}, qr/JSON_OBJECT/,
        'fields includes JSON_OBJECT call' );
    like( $got{fields}, qr/services\.name/,
        'fields includes services.name' );
    like( $got{fields}, qr/services\.cost/,
        'fields includes services.cost' );
    like( $got{fields}, qr/services\.category/,
        'fields includes services.category' );
    like( $got{fields}, qr/AS service/i,
        'fields includes AS service alias' );
};

# ---------------------------------------------------------------------------
# 2. join is always set to the services table
# ---------------------------------------------------------------------------
subtest 'list_for_api - join is set to services table' => sub {
    my %got = call_and_capture();

    cmp_deeply(
        $got{join},
        { table => 'services', using => ['service_id'] },
        'join links user_services to services via service_id',
    );
};

# ---------------------------------------------------------------------------
# 3. category arg is added to where
# ---------------------------------------------------------------------------
subtest 'list_for_api - category is added to where when provided' => sub {
    my %got = call_and_capture( category => 'vpn' );

    is( $got{where}{category}, 'vpn',
        'category value is placed into where' );
};

subtest 'list_for_api - category is absent from where when not provided' => sub {
    my %got = call_and_capture();

    ok( !exists $got{where}{category},
        'category key is not present in where when not passed' );
};

# ---------------------------------------------------------------------------
# 4. Other caller args pass through to the parent unchanged
# ---------------------------------------------------------------------------
subtest 'list_for_api - extra args pass through to parent' => sub {
    my %got = call_and_capture(
        limit          => 10,
        sort_direction => 'asc',
        sort_field     => 'created',
    );

    is( $got{limit},          10,      'limit passes through' );
    is( $got{sort_direction}, 'asc',   'sort_direction passes through' );
    is( $got{sort_field},     'created', 'sort_field passes through' );
};

# ---------------------------------------------------------------------------
# 5. Caller-supplied fields is silently replaced by the internal expression
# ---------------------------------------------------------------------------
subtest 'list_for_api - caller fields is always overridden' => sub {
    my %got = call_and_capture( fields => 'user_id' );

    like( $got{fields}, qr/JSON_OBJECT/,
        'caller-supplied fields is replaced by internal SQL expression' );
    unlike( $got{fields}, qr/^user_id$/,
        'simple caller fields does not reach parent as-is' );
};

done_testing();
