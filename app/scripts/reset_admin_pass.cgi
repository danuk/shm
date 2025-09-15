#!/usr/bin/perl

use v5.14;

use SHM qw(:all);

my $user_id = $ARGV[0] || 1;
my $user =  SHM->new( user_id => $user_id );
unless ( $user ) {
    say "Error: user not exists";
    exit 1;
}

$user->set(
    gid => 1,
    block => 0,
);

say "The password has been changed:";
say sprintf("Login: %s", $user->get_login );
say sprintf("Password: %s", $user->set_new_passwd( len => 16 + int(rand(5)) ) );

$user->commit;

exit 0;

