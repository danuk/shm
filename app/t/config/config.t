use strict;
use warnings;

use Test::More;
use Test::Deep;

use v5.14;
use utf8;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $config = get_service("config")->data_by_name;

is( $config->{company_name}, 'My Company LTD', 'Check company name' );

done_testing();
