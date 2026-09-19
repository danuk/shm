use v5.14;
use utf8;

# Regression test for: anonymous client impersonation via /public/* templates.
#
# /public/* is designed to run under a fixed, unauthenticated context
# (user_id => 1 in the route config). It must never allow an anonymous
# caller to switch the effective "current user" by appending ?user_id=N,
# otherwise templates that reference the current user (e.g. {{ user.id }})
# would leak another client's data.

use Core::Utils qw/shm_test_api/;
use Core::System::ServiceManager qw( get_service );
use SHM;

use Test::More;

my $tpl_id = 'security_test_public_user_switch';
my $victim_user_id = 40092;

# Create the public template directly via the service (shm_test_api only
# supports flat scalar payloads over HTTP, and settings is a nested object).
SHM->new( user_id => 1 );
my $tpl = get_service('template');
$tpl->add(
    id => $tpl_id,
    data => '{{ user.id }}',
    settings => { allow_public => 1 },
);
ok $tpl->id( $tpl_id ), 'Public template created' or diag explain get_service('report')->errors;

my %baseline = shm_test_api(
    url => "v1/public/$tpl_id",
);
is $baseline{content}, '1', 'Anonymous request runs under the fixed public user context';

my %attack = shm_test_api(
    url => "v1/public/$tpl_id?user_id=$victim_user_id",
);
is $attack{content}, '1', 'Anonymous ?user_id override on /public/* is ignored';
isnt $attack{content}, "$victim_user_id", 'Victim client data is not leaked via /public/*';

get_service('template')->_delete( id => $tpl_id );

done_testing();

exit 0;
