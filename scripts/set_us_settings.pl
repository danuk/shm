#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
use Core::System::ServiceManager qw( get_service );

my $us = SHM->new()->user->services;

my $data = $us->tree->with('settings')->get;

update( $data );

exit;

sub update {
    my $data = shift;

    for my $usi ( keys %{ $data } ) {

        say $usi;
        get_service('us', _id => $usi )->settings( $data->{ $usi }->{settings} )->settings_save;

        if ( $data->{ $usi }->{children} ) {
            update( $data->{ $usi }->{children} );
        }
    }
}

exit 0;
