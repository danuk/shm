use v5.14;

use Test::More;
use Core::Billing;

{
    package Test::Bonus::Service;
    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub config { shift->{config} || {} }
}

is( Core::Billing::calc_available_bonuses( undef, 100, 100 ), 0, 'no service -> zero bonuses' );
is( Core::Billing::calc_available_bonuses( Test::Bonus::Service->new, 0, 100 ), 0, 'zero user bonus -> zero bonuses' );

is(
    Core::Billing::calc_available_bonuses(
        Test::Bonus::Service->new( config => {} ),
        100,
        50,
    ),
    100,
    'no limit_bonus_percent -> full bonuses are available',
);

is(
    Core::Billing::calc_available_bonuses(
        Test::Bonus::Service->new( config => { limit_bonus_percent => 100 } ),
        100,
        10,
    ),
    100,
    'limit 100 -> full bonuses are available',
);

is(
    Core::Billing::calc_available_bonuses(
        Test::Bonus::Service->new( config => { limit_bonus_percent => 50 } ),
        150,
        200,
    ),
    100,
    'limit 50% -> bonus is capped by total * 50%',
);

is(
    Core::Billing::calc_available_bonuses(
        Test::Bonus::Service->new( config => { limit_bonus_percent => 50 } ),
        100,
        0,
    ),
    0,
    'limit below 100 with zero total -> zero bonuses',
);

is(
    Core::Billing::calc_available_bonuses(
        Test::Bonus::Service->new( config => { limit_bonus_percent => 33 } ),
        100,
        100,
    ),
    33,
    'limit 33% -> rounded capped bonus',
);

done_testing();
