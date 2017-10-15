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

# Load childs
my $childs = $us->res( $parents )->childs->category('web','mail','mysql')->with('services','settings','server','domains')->get;

# Add childs to structure
for my $c ( keys %{ $childs } ) {
    $parents->{ $childs->{$c}->{parent} }->{services}->{ $childs->{$c}->{category} }->{ $childs->{$c}->{user_service_id } } = $childs->{$c};
}

print_json( $parents );

exit 0;
