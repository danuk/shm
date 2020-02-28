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

my $config = get_service("config");
my $data = $config->data_by_name;

is( $data->{company_name}, 'My Company LTD', 'Check company name' );
is( $config->id('company_name')->get->{value}, 'My Company LTD' );

my $key = $config->add(
    key => 'new_param',
    value => 'edc',
);

is( $key, 'new_param');

my $test = get_service("config", _id => 'mail_from');
is( $test->get->{value}, 'mail@domain.ru' );

$test->set( value => "QAZ" );
is( $test->get->{value}, 'QAZ' );


done_testing();
