#!/usr/bin/perl

use v5.14;

use SHM qw(:all);

my $user_id = $ARGV[0] || 1;
my $user =  SHM->new( user_id => $user_id );
unless ( $user ) {
    say "Error: user not exists";
    exit 1;
}

$user->set_settings({ password_auth_disabled => 0 }) if $user->settings->{password_auth_disabled};

say "The password authentication enabled";
say sprintf("Login: %s", $user->get_login );

$user->commit;

exit 0;
