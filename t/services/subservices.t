use v5.14;

use Test::More;
use Data::Dumper;

use SHM;
my $us = SHM->new( user_id => 40092 );

use Core::System::ServiceManager qw( get_service );

my $ret = get_service('us', _id => 99)->subservices;

is_deeply( keys %{ $ret } == 3 && exists $ret->{59} && exists $ret->{117} && exists $ret->{58}, 1, 'get sub services');


done_testing();
