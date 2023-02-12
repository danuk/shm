#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user =  SHM->new( user_id => 1 );

say "Password has changed:";
say sprintf("Login: %s", $user->get_login );
say sprintf("Password: %s", $user->set_new_passwd( len => 16 ) );

$user->commit;

exit 0;

