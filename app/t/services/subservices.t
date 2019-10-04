use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

use SHM;
my $us = SHM->new( user_id => 40092 );

use Core::System::ServiceManager qw( get_service );

my @ret = get_service('service', _id => 4)->subservices;

cmp_deeply( [ map $_->{subservice_id}, @ret ], bag(5,8,29) );

done_testing();
