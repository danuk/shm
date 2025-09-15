#!/usr/bin/perl

use v5.14;

use SHM qw(:all);

my $user_id = $ARGV[0] || 1;
my $user =  SHM->new( user_id => $user_id );
unless ( $user ) {
    say "Error: user not exists";
    exit 1;
}

my $session_id = $user->gen_session()->{id};
my $url = get_service('config', _id => 'api')->get_data->{url};

say sprintf("%s?session_id=%s", $url, $session_id );
say sprintf("curl --cookie \"session_id=%s\" %s/shm/v1/admin/", $session_id, $url );

$user->commit;

exit 0;

