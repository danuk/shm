use v5.14;

use Test::More;
use Data::Dumper;

use SHM;
use Core::System::ServiceManager qw( get_service );

my $user = SHM->new( user_id => 40092 );
is ( $user->id, 40092 );

my $us = get_service('us', _id => 101 );
is ( $us->id, 101 );

my $us1 = get_service('us', _id => 9999 );
is ( $us1, undef, 'Try to get non exist service');

my $us2 = get_service('us', _id => '' );
is ( $us2, undef, 'Try to get unknown service');

my $us3 = get_service('us', _id => 0 );
is ( $us3, undef, 'Try to get zero service');

my $us_parent = $us->parent;
is ( $us_parent->id, 99 );

my $ss_1 = get_service('service', _id => 1 );
my $ss_2 = get_service('service', _id => 2 );

is ( $ss_1->id, 1 );
is ( $ss_2->id, 2 );
is ( get_service('service', _id => 1)->id,  1 );

is ( get_service('service', _id => 1)->get->{service_id},  1 );

my $pay = get_service('pay', _id => 1, foo => 1, bar => 2 );
is ( $pay->{foo} == 1 && $pay->{bar} == 2, 1, 'Check set variables to object' );

subtest 'Check us user_id inherit' => sub {
    my $user1 = $user->id(40092);
    my $user2 = $user->id(40094);

    my $t1 = $user1->us;
    my $t2 = $user2->us;

    is( $t1->{user_id}, 40092 );
    is( $t2->{user_id}, 40094 );
};


done_testing();
