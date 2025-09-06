use v5.14;
use utf8;

use Core::Utils qw/shm_test_api/;
use Test::More;
use Test::Deep;
use Core::System::ServiceManager qw( get_service );

subtest 'Attempt to send a user password reset request' => sub {
    my %ret = shm_test_api(
        url => 'v1/user/passwd/reset',
        method => 'POST',
        data => {
            email => 'danuk',
        },
    );

    is $ret{success}, 1;
};

subtest 'Delete password reset request from spool' => sub {
    use SHM;
    my $user = SHM->new( user_id => 40092 );

    my $spool = get_service('spool');
    my ( $row ) = $spool->list;

    cmp_deeply( $row, superhashof({
          user_id => 40092,
          prio => 0,
          status => 'NEW',
          settings => undef,
          user_service_id => undef,
          response => undef,
          event => {
              id => 1,
              name => 'USER_PASSWORD_RESET',
              kind => 'UserService',
              server_gid => 3,
              settings => {
                  template_id => 'user_password_reset',
                  category => '%',
              },
              title => 'User password reset',
          },
          delayed => 0,
          executed => undef,
    }));

    $spool->id( $row->{id} )->delete();
    $user->passwd( password => 'danuk' );
    $user->commit();
};

done_testing();

exit 0;

