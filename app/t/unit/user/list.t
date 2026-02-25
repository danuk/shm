use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

my @list = $user->list();
is( grep( $_->{block} == 1, @list ), 0, 'Check list' );

my @_list = $user->_list();
is( grep( $_->{block} == 1, @_list ), 0, 'Check list internal' );

my @list_blocked = $user->list( where => { block => 1 } );
is( grep( $_->{block} == 1, @list_blocked ), 1, 'Check list blocked' );

my @_list_blocked = $user->_list( where => { block => 1 } );
is( grep( $_->{block} == 1, @_list_blocked ), 1, 'Check list blocked internal' );

my @list_for_api = $user->list_for_api();
is( grep( $_->{block} == 1, @list_for_api ), 0, 'Check list_for_api' );

my $items = $user->items();
is( grep( $_->is_blocked == 1, @$items ), 0, 'Check items' );

my $items_admin = $user->items( admin => 1 );
is( grep( $_->is_blocked == 1, @$items_admin ), 0, 'Check items for admin' );

my $user_removed = $user->id( 40093 );
is( defined $user_removed, 1, 'Check direct get deleted user');

my ( $user_list_removed ) = $user->list( where => { user_id => 40093 } );
is( $user_list_removed->{block}, 1, 'Check get deleted user by query');

done_testing();
