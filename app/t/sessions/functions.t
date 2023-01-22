use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;
my $user = SHM->new( user_id => 40092 );

subtest 'Check user gen_session()' => sub {
    my $user_session = $user->gen_session();
    my $user_session_id = $user_session->{id};

    is( defined $user_session_id, 1 , 'Check gen_session()');
    is( length $user_session_id , 32 , 'Check gen_session() length');

    my $session = get_service('sessions', _id => $user_session_id );
    is ( $session->id eq $user_session_id, 1, 'Check Session module' );
};

subtest 'Check session add' => sub {
    my $new_session = get_service('sessions')->add();
    my $session = get_service('sessions', _id => $new_session );
    is ( $session->get_user_id, 40092, 'Check session user_id' );
};

subtest 'Check session add with custom parameters' => sub {
    my $new_session = get_service('sessions')->add(
        user_id => 1,
        settings => {},
    );
    my $session = get_service('sessions', _id => $new_session );
    is ( $session->get_user_id, 1, 'Check session user_id' );
};

done_testing();
