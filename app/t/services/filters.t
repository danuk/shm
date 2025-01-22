use strict;
use warnings;

use v5.14;
use Test::More;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;

use SHM;
my $user = SHM->new( user_id => 40092 );

subtest 'test category LIKE' => sub {
    my @items = $user->us->filter( category => 'web_%' )->items;
    is( scalar @items, 1 );
};

subtest 'test two params' => sub {
    my @items = $user->us->filter( category => 'web_%', user_service_id => 99)->items;
    is( scalar @items, 1 );
};

subtest 'test settings exists' => sub {
    my @items = $user->us->filter( settings => 'ns' )->items;
    is( scalar @items, 6 );
};

subtest 'test settings EQ param' => sub {
    my @items = $user->us->filter( settings => { ns => 'ns1.viphost.ru' } )->items;
    is( scalar @items, 2 );
};

subtest 'test settings NON param' => sub {
    my @items = $user->us->filter( settings => { ns => { '!=' => 'ns1.viphost.ru' } } )->items;
    is( scalar @items, 4 );
};

subtest 'test sort and rsort' => sub {
    my @items = $user->us->sort('user_id','created')->rsort('category')->items;
    is( scalar @items, 19 );
};

subtest 'test sort ' => sub {
    my @items = $user->sort('user_id')->items;
    is( $items[0]->id, 1 );
};

subtest 'test rsort ' => sub {
    my @items = $user->rsort('user_id')->items;
    is( $items[0]->id, 40094 );
};

done_testing();

