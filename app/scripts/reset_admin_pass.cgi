#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
use Core::Utils qw(
    passgen
);

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

$user->set_settings({ strict_ip_mode => 0 }) if $user->settings->{strict_ip_mode};

say "The password has been changed:";
say sprintf("Login: %s", $user->get_login );

my $user_primary_login = $user->get_login;
my $login = $user->logins->id( $user_primary_login );
unless ( $login ) {
    if ( $user->logins->add( login => $user_primary_login ) ) {
        $login = $user->logins->id( $user_primary_login );
    }
}

unless ( $login ) {
    say "Error: can't create a new login";
    exit 1;
}

my $new_password = passgen( 32 );
$login->set_password( $new_password );

say sprintf("Password: %s", $new_password );

$user->commit;

exit 0;

