use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::Pay;
use Core::Billing;

{
    package Test::Forecast::User;
    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub id { shift->{id} }
    sub get_balance { shift->{balance} }
    sub get_bonus { shift->{bonus} }
    sub get_discount { shift->{discount} }
}

{
    package Test::Forecast::Service;
    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub id { shift->{id} }
    sub get_cost { shift->{cost} }
    sub get_period { shift->{period} }
    sub get_name { shift->{name} }
    sub convert_name { my ( $self, $name ) = @_; return $name }
    sub config { shift->{config} || {} }
    sub get {
        my $self = shift;
        my $cfg = $self->config;
        return (
            id => $self->{id},
            service_id => $self->{id},
            name => $self->{name},
            cost => $self->{cost},
            period => $self->{period},
            no_discount => $cfg->{no_discount} ? 1 : 0,
        );
    }
}

{
    package Test::Forecast::Withdraw;
    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub get { %{ shift->{get} || {} } }
    sub next { %{ shift->{next} || {} } }
    sub paid { shift->{paid} ? 1 : 0 }
}

{
    package Test::Forecast::US;
    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub withdraw { shift->{withdraw} }
    sub wd { shift->{withdraw} }
    sub service { shift->{service} }
    sub billing { shift->{billing} || 'Simpler' }
}

{
    package Test::Forecast::USList;
    sub new { bless { data => $_[1] }, $_[0] }
    sub list_prepare { shift }
    sub with { shift }
    sub get { shift->{data} }
}

{
    package Test::Forecast::Pay;
    use parent -norequire, 'Core::Pay';
    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub user { shift->{user_obj} }
    sub user_id { shift->{user_id} }
}

{
    package Test::Forecast::Discounts;
    sub new { bless {}, shift }
    sub get_by_period { return undef }
}

sub _expected {
    my %args = @_;

    my $discount = $args{no_discount} ? 0 : $args{user_discount};
    my $total_before_bonus = $args{cost} - ( $args{cost} * $discount / 100 );

    my $bonus_cap;
    if ( !defined $args{limit_bonus_percent} || int( $args{limit_bonus_percent} ) >= 100 ) {
        $bonus_cap = $args{bonus};
    } else {
        $bonus_cap = $total_before_bonus * int( $args{limit_bonus_percent} ) / 100;
    }

    my $bonus_applied = $args{bonus} < $bonus_cap ? $args{bonus} : $bonus_cap;
    $bonus_applied = $total_before_bonus if $bonus_applied > $total_before_bonus;

    my $item_total = $total_before_bonus - $bonus_applied;
    $item_total = 0 if $item_total < 0;

    my $total = $item_total;
    my $dept;

    if ( $item_total > 0 ) {
        if ( $args{balance} > 0 ) {
            $total -= $args{balance};
            $total = 0 if $total < 0;
        } else {
            $dept = abs( $args{balance} );
            $total += $dept;
        }
    } else {
        $total = 0;
    }

    return {
        item_total => $item_total + 0,
        total => $total + 0,
        dept => ( defined $dept ? $dept + 0 : undef ),
        discount => $discount + 0,
    };
}

sub _run_forecast {
    my %args = @_;

    my $user = Test::Forecast::User->new(
        id => 70001,
        balance => $args{balance},
        bonus => $args{bonus},
        discount => $args{user_discount},
    );

    my $current_service = Test::Forecast::Service->new(
        id => 10,
        name => 'Current Service',
        cost => $args{current_cost},
        period => 1,
        config => {
            limit_bonus_percent => defined $args{current_limit_bonus_percent}
                ? $args{current_limit_bonus_percent}
                : $args{limit_bonus_percent},
            no_discount => defined $args{current_no_discount}
                ? ($args{current_no_discount} ? 1 : 0)
                : ($args{no_discount} ? 1 : 0),
        },
    );

    my $next_service = Test::Forecast::Service->new(
        id => 20,
        name => 'Next Service',
        cost => $args{next_cost},
        period => 1,
        config => {
            limit_bonus_percent => defined $args{next_limit_bonus_percent}
                ? $args{next_limit_bonus_percent}
                : $args{limit_bonus_percent},
            no_discount => defined $args{next_no_discount}
                ? ($args{next_no_discount} ? 1 : 0)
                : ($args{no_discount} ? 1 : 0),
        },
    );

    my %services = (
        10 => $current_service,
        20 => $next_service,
    );

    my $withdraw = Test::Forecast::Withdraw->new(
        paid => 1,
        get => {
            service_id => 10,
            cost => $args{wd_cost},
            months => 1,
            qnt => 1,
            discount => 0,
            total => $args{wd_cost},
            withdraw_date => '2020-01-01 00:00:00',
        },
        next => {},
    );

    my $us = Test::Forecast::US->new(
        service => $current_service,
        withdraw => $withdraw,
    );

    my %user_services_data = (
        100 => {
            next => $args{next_field},
            service_id => 10,
            user_service_id => 100,
            status => 'ACTIVE',
            expire => $args{expire},
            settings => {},
            services => { name => 'Current Service' },
            withdraws => {
                cost => $args{wd_cost},
                months => 1,
                qnt => 1,
                discount => 0,
                total => $args{wd_cost},
            },
        },
    );

    my $us_list = Test::Forecast::USList->new( \%user_services_data );

    my $pay = Test::Forecast::Pay->new(
        user_id => 70001,
        user_obj => $user,
    );

    my %ctx = (
        user => $user,
        us => { 100 => $us },
        services => \%services,
        us_list => $us_list,
        discounts => Test::Forecast::Discounts->new,
    );

    no warnings 'redefine';

    local *Core::Pay::user = sub { $ctx{user} };
    local *Core::Pay::user_id = sub { $ctx{user}->id };
    local *Core::Pay::switch_user = sub { 1 };

    local *Core::Pay::get_service = sub {
        my ( $name, %svc_args ) = @_;

        return $ctx{us_list} if $name eq 'UserService';
        return $ctx{us}->{ $svc_args{_id} } if $name eq 'us';
        return $ctx{services}->{ $svc_args{_id} } if $name eq 'service';

        return undef;
    };

    local *Core::Billing::get_service = sub {
        my ( $name, %svc_args ) = @_;

        return $ctx{services}->{ $svc_args{_id} } if $name eq 'service';
        return $ctx{user} if $name eq 'user';
        return $ctx{discounts} if $name eq 'discounts';

        return undef;
    };

    return $pay->forecast();
}

sub _assert_common {
    my ( $forecast, $expected, $expected_service_id ) = @_;

    if ( $expected->{item_total} > 0 ) {
        is( scalar @{ $forecast->{items} || [] }, 1, 'one item included in forecast' );
        is( $forecast->{items}[0]{next}{service_id}, $expected_service_id, 'expected next service selected' );
        is( $forecast->{items}[0]{next}{total} + 0, $expected->{item_total}, 'item total is expected' );
        is( $forecast->{items}[0]{next}{discount} + 0, $expected->{discount}, 'discount is expected' );
    } else {
        is( scalar @{ $forecast->{items} || [] }, 0, 'item excluded when nothing to pay' );
    }

    is( $forecast->{total} + 0, $expected->{total}, 'final total is expected' );

    if ( defined $expected->{dept} ) {
        is( $forecast->{dept} + 0, $expected->{dept}, 'debt is expected when balance is negative' );
    }
}

sub _run_matrix {
    my %args = @_;

    my @cases = (
        { balance => 100, bonus => 0 },
        { balance => -50, bonus => 0 },
        { balance => 100, bonus => 100 },
        { balance => -50, bonus => 100 },
    );

    for my $c ( @cases ) {
        my $label = sprintf('%s: balance=%s bonus=%s', $args{label}, $c->{balance}, $c->{bonus});
        subtest $label => sub {
            my $forecast = _run_forecast(
                balance => $c->{balance},
                bonus => $c->{bonus},
                user_discount => 10,
                no_discount => 0,
                limit_bonus_percent => 50,
                wd_cost => 150,
                current_cost => 200,
                next_cost => 300,
                next_field => $args{next_field},
                expire => '2020-01-01 00:00:00',
            );

            my $expected = _expected(
                cost => $args{expected_cost},
                user_discount => 10,
                no_discount => 0,
                limit_bonus_percent => 50,
                bonus => $c->{bonus},
                balance => $c->{balance},
            );

            _assert_common( $forecast, $expected, $args{expected_service_id} );
        };
    }
}

subtest 'next = -1 and expired is excluded from forecast' => sub {
    my $forecast = _run_forecast(
        balance => 0,
        bonus => 0,
        user_discount => 10,
        no_discount => 0,
        limit_bonus_percent => 50,
        wd_cost => 150,
        current_cost => 200,
        next_cost => 300,
        next_field => -1,
        expire => '2020-01-01 00:00:00',
    );

    is( scalar @{ $forecast->{items} || [] }, 0, 'service is excluded' );
    is( $forecast->{total} + 0, 0, 'total is zero when excluded' );
};

_run_matrix(
    label => 'next empty -> prolong with previous conditions',
    next_field => undef,
    expected_cost => 150,
    expected_service_id => 10,
);

_run_matrix(
    label => 'next = current service id -> recalculate from service',
    next_field => 10,
    expected_cost => 200,
    expected_service_id => 10,
);

_run_matrix(
    label => 'next = other service id -> recalculate from other service',
    next_field => 20,
    expected_cost => 300,
    expected_service_id => 20,
);

for my $case (
    { label => 'next empty', next_field => undef, expected_cost => 150, expected_service_id => 10 },
    { label => 'next current', next_field => 10, expected_cost => 200, expected_service_id => 10 },
    { label => 'next other', next_field => 20, expected_cost => 300, expected_service_id => 20 },
) {
    subtest "$case->{label} - no_discount disables personal discount" => sub {
        my $forecast = _run_forecast(
            balance => 0,
            bonus => 100,
            user_discount => 10,
            no_discount => 1,
            limit_bonus_percent => 50,
            wd_cost => 150,
            current_cost => 200,
            next_cost => 300,
            next_field => $case->{next_field},
            expire => '2020-01-01 00:00:00',
        );

        my $expected = _expected(
            cost => $case->{expected_cost},
            user_discount => 10,
            no_discount => 1,
            limit_bonus_percent => 50,
            bonus => 100,
            balance => 0,
        );

        _assert_common( $forecast, $expected, $case->{expected_service_id} );
    };

    subtest "$case->{label} - full bonus mode (100%)" => sub {
        my $forecast = _run_forecast(
            balance => 0,
            bonus => 100,
            user_discount => 10,
            no_discount => 0,
            limit_bonus_percent => 100,
            wd_cost => 150,
            current_cost => 200,
            next_cost => 300,
            next_field => $case->{next_field},
            expire => '2020-01-01 00:00:00',
        );

        my $expected = _expected(
            cost => $case->{expected_cost},
            user_discount => 10,
            no_discount => 0,
            limit_bonus_percent => 100,
            bonus => 100,
            balance => 0,
        );

        _assert_common( $forecast, $expected, $case->{expected_service_id} );
    };
}

subtest 'next=other uses bonus policy of next service' => sub {
    my $forecast = _run_forecast(
        balance => 0,
        bonus => 90,
        user_discount => 0,
        no_discount => 0,
        current_limit_bonus_percent => 0,
        next_limit_bonus_percent => 100,
        wd_cost => 150,
        current_cost => 200,
        next_cost => 100,
        next_field => 20,
        expire => '2020-01-01 00:00:00',
    );

    is( scalar @{ $forecast->{items} || [] }, 1, 'one item included in forecast' );
    is( $forecast->{items}[0]{next}{service_id}, 20, 'next service is selected' );
    is( $forecast->{items}[0]{next}{bonus} + 0, 90, 'bonuses are calculated by next service policy' );
    is( $forecast->{items}[0]{next}{total} + 0, 10, 'total reflects full next-service bonus allowance' );
    is( $forecast->{total} + 0, 10, 'final total matches item total without balance adjustment' );
};

done_testing();
