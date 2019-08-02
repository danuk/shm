use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

use SHM;
SHM->new( user_id => 40092 );

use Core::Const;
use Core::System::ServiceManager qw( get_service );

my $us = get_service('UserService');

my $obj = $us->id(99)->get;
is exists $obj->{99}, 1, 'get user_service from id';

is_deeply( $obj, {
    99 => {
        parent => undef,
        next => 0,
        auto_bill => 1,
        status => STATUS_ACTIVE,
        service_id => 110,
        user_service_id => 99,
        settings => {
            quota => 10000
        },
        created => '2014-10-07 12:56:09',
        expired => '2017-01-31 23:59:50',
        user_id => 40092,
        withdraw_id => 3691,
    }
}, 'get user_service from id (check full structure)');

$obj = $us->parents->get;
cmp_deeply( [ keys %{ $obj } ], bag( 16,19,99,2949 ), 'get user_services parents');

$obj = $us->parents->children->get;
cmp_deeply( [ keys %{ $obj } ], bag( 17,18,20,21,100,101,102,2950,2951 ), 'get user_services children for parents');

$obj = $us->parents->category('web_tariff')->get;
cmp_deeply( [ keys %{ $obj } ], bag( 99 ), 'get user_services parents filtered by web_tariff');

$obj = $us->parents->category('web_tariff')->children->get;
cmp_deeply( [ keys %{ $obj } ], bag( 100, 101, 102 ), 'get user_services children for parents filtered by web_tariff');

$obj = $us->parents->category('web_tariff')->children->category('web')->get;
cmp_deeply( [ keys %{ $obj } ], bag( 101 ), 'get user_services children for parents filtered by web_tariff and only web child');

$obj = $us->parents->category('web_tariff')->children->category('web')->with('settings','domains')->get;

is( exists $obj->{101}->{settings}, 1, 'get user_services children for parents filtered by web_tariff and only web child with settings' );
is( exists $obj->{101}->{domains}, 1, 'get user_services children for parents filtered web_tariff and only web child with domains' );
is( $obj->{101}->{name}, 'Web хостинг (3391 мб)', 'get user_services children for parents filtered web_tariff and only web child. Check name field fill' );

$obj = $us->tree->get;
is( $obj->{16}->{children}->{17}->{created}, '2014-10-02 13:47:30', 'Check full tree' );

$obj = $us->tree->with('settings','server')->get;
is( $obj->{16}->{children}->{17}->{settings}->{server_id}, '1', 'Check full tree with settings' );

$obj = $us->parents->tree->with('settings')->get;
is( $obj->{16}->{children}->{17}->{settings}->{server_id}, '1', 'Check full tree with settings (tree by parents)' );
is( $obj->{2949}->{children}->{2951}->{created}, '2016-07-29 12:39:08', 'Check full tree for parents' );
is( $obj->{2949}->{children}->{2951}->{settings}->{master}, '185.31.160.56', 'Check full tree for parents and settings' );

$obj = $us->parents->category('web_tariff')->tree->with('settings')->get;
is( $obj->{99}->{children}->{101}->{children}->{2942}->{settings}->{domain}, 'shm.danuk.ru', 'Check full tree for parents filtered by web_tariff with settings' );

$obj = $us->id(99)->with('settings','withdraws')->get;
is ( exists $obj->{99}->{withdraws}, 1, 'Check withdraws load for service');

$obj = $us->id(101)->with('settings','servers')->get;
is ( exists $obj->{101}->{servers}->{host}, 1, 'Check service with servers');

$obj = $us->ids( user_service_id => [ 99,101 ] )->with('settings')->get;
is ( exists $obj->{101}->{settings}->{quota}, 1, 'Check load services by user_service_id array' );

done_testing();
