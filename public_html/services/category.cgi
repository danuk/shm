#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $us = SHM->new()->services;

use Core::Utils qw(
    parse_args
);

our %in = parse_args();

my $parents;

# Load parents
if ( $in{tariff_id} ) {
    $parents = $us->id( $in{tariff_id} );
}
else {
    $parents = $us->parents;
}

# Add data to parents
$parents = $parents->category( qw/web_tariff web_virt web_tariff web_tariff_free web_tariff_priv dedicated_hostin/ )->with('services','settings','withdraws')->get;

# Load children
my $children = $us->res( $parents )->children->category('web','mail','mysql')->with('services','settings','server','domains')->get;

# Add children to structure
for my $c ( keys %{ $children } ) {
    $parents->{ $children->{$c}->{parent} }->{services}->{ $children->{$c}->{category} }->{ $children->{$c}->{user_service_id } } = $children->{$c};
}

print_json( $parents );

exit 0;
