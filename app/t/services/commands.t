use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;

$ENV{SHM_TEST} = 1;

use SHM;
SHM->new( user_id => 40092 );

use Core::System::ServiceManager qw( get_service );

my $obj = get_service('Events');

my @ret = $obj->get_events( kind => 'UserService', category => 'mysql', name => 'remove' );

is @ret, 1;

done_testing();
