use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my @list = get_service('acts')->list( limit => 5 );

is( $list[0]->{user_id}, 40092, 'Check param in list of acts');
is( scalar( @list ), 5, 'Check count of acts list');

my @data = get_service('ActsData')->list( where => { act_id => 195 } );
is( $data[0]->{act_id}, 195, 'Check param in list of acts');

my ( $acts_data ) = get_service('ActsData')->list( where => { id => 482 } );
is( $acts_data->{id}, 482, 'Check param in acts_data');

done_testing();
