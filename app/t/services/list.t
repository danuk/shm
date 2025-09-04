use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

my @list = $user->us->list();
is( grep( $_->{status} eq 'REMOVED', @list ), 0, 'Check list' );

my @_list = $user->us->_list();
is( grep( $_->{status} eq 'REMOVED', @_list ), 0, 'Check list internal' );

my @list_blocked = $user->us->list( where => { status => 'REMOVED' } );
is( grep( $_->{status} eq 'REMOVED', @list_blocked ), 1, 'Check list blocked' );

my @_list_blocked = $user->us->_list( where => { status => 'REMOVED' } );
is( grep( $_->{status} eq 'REMOVED', @_list_blocked ), 1, 'Check list blocked internal' );

my @list_for_api = $user->us->list_for_api();
is( grep( $_->{status} eq 'REMOVED', @list_for_api ), 0, 'Check list_for_api' );

my ( $list_for_api_by_id ) = $user->us->list_for_api( where => { user_service_id => 2945 } );
is( $list_for_api_by_id->{status} eq 'REMOVED', 1, 'Check list_for_api by id' );

my ( $list_for_api_by_id_and_status ) = $user->us->list_for_api( where => { user_service_id => 2945, status => 'ACTIVE' } );
is( defined $list_for_api_by_id_and_status, '', 'Check list_for_api by id and status' );

my $items = $user->us->items();
is( grep( $_->get_status eq 'REMOVED', @$items ), 0, 'Check items' );

my $items_admin = $user->us->items( admin => 1 );
is( grep( $_->get_status eq 'REMOVED', @$items_admin ), 0, 'Check items for admin' );

my $us = $user->us->id( 2945 );
is( defined $us, 1, 'Check direct get removed us' );

done_testing();
