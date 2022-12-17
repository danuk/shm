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

is( $data->{company}->{name}, 'My Company LTD', 'Check company name' );
is( $config->id('company')->get->{value}->{name}, 'My Company LTD' );
is( $config->id('company')->get_data->{name}, 'My Company LTD' );

my $key = $config->add(
    key => 'new_param',
    value => {"edc" => 1},
);

is( $key, 'new_param');

my $test = get_service("config", _id => 'mail');
is( $test->get_data->{from}, 'mail@domain.ru' );

$test->set( value => { "QAZ" => 1} );
is( $test->get_data->{"QAZ"}, 1 );

my $version = $config->id( '_shm')->get_data;
cmp_deeply( $version, {
    version => ignore(),
});

done_testing();
