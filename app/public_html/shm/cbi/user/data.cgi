#!/usr/bin/perl

use v5.14;
use SHM qw(:all);

my $res = SHM->new()->get;

delete $res->{password};

# TODO:
# wcast = forecast
# can_edit = check in passport
# pin
# dog

$res->{dog} = $res->{user_id};

print_json( $res );

exit 0;

