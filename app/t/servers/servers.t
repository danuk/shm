use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;

use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;

use SHM;
my $us = SHM->new( user_id => 40092 );

my $server = get_service('server', _id => 1 );

is ( $server->get_services_count, 25 );

$server->services_count_increase;
is ( $server->get_services_count, 26 );

$server->services_count_decrease;
is ( $server->get_services_count, 25 );

is ( $server->group->get_name, 'Сервера Web хостинга' );

done_testing();
