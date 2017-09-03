use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my @list = get_service('app')->list;

is( $list[0]->{user_id}, 40092, 'Check param in list of apps');
is( scalar( @list ), 2, 'Check count of apps list');


done_testing();
