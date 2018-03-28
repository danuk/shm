use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;

$ENV{SHM_TEST} = 1;

use SHM;
SHM->new( user_id => 40092 );

use Core::System::ServiceManager qw( get_service );

my $obj = get_service('us', _id => 99);

my @arr = $obj->withdraws->list;
is ( $arr[0]->{cost}, 0, 'Get cost of list withdraws array' );

my $wd = $obj->withdraws->get;
is ( $wd->{cost}, 0, 'Get cost of current withdraw (hash mode)' );

is ( $obj->withdraws->get->{cost}, 0, 'Get cost of current withdraw (ref mode)' );

my $new_wd_id = $obj->withdraws->add( %{ $wd } );
my $new_wd = get_service('wd', _id => $new_wd_id );
is ( int( $new_wd->{withdraw_id} > $wd->{withdraw_id} ), 1, 'Check add new withdraw' );

my %next_wd = $obj->withdraws->next;
is ( exists $new_wd->{withdraw_id}, 1, 'Check get one next withdraw' );

my $nexts = $obj->withdraws->next;
is ( ref $nexts eq 'ARRAY', 1, 'Check get all nexts withdraw' );

done_testing();
