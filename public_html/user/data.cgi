#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $cli = SHM->new();

my $res = $cli->user->get;

delete $res->{password};

# TODO:
# wcast = forecast
# can_edit = check in passport
# pin
# dog

print_json( $res );

exit 0;

