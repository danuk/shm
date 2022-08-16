#!/usr/bin/perl

use strict;
use v5.14;

my $cgi = CGI->new;

use CGI::Carp qw(fatalsToBrowser);

use Core::Utils qw(
    parse_args
);

my %in = parse_args();

if ( $in{session_id} ) {
    print_header(
        cookie => create_cookie('session_id',$in{session_id}),
        location => '/',
        status => 302,
    );
    exit 0;
}

use Core::System::ServiceManager qw( get_service );

my $session = get_service('sessions');
if ($session->id( $in{session_id} ) ) {
    print_json( { status => 0, msg => 'Already authorized', session_id => $session->id, user_id => $session->user_id } );
	exit 0;
}

unless ( $in{login} && $in{password} ) {
	print_json( { status => 400, msg => 'login or password not present' } );
	exit 0;
}

use SHM qw(:all);
my $user = SHM->new( skip_check_auth => 1 );

unless ( $user = $user->auth( login => trim($in{login}), password => trim($in{password}) )) {
    print_json( { status => 401, msg => 'Incorrect login or password' } );
	exit 0;
}

if ( $in{admin} && !$user->is_admin ) {
    print_json( { status => 403, msg => 'Forbidden: user is not admin' } );
    exit 0;
}

$session->add(
    user_id => $user->id,
);

my $session_id = $session->id;

print_header( cookie => create_cookie('session_id',$session_id) );
print_json( { status => 200, msg => 'Successfully', session_id => $session_id, user_id => $user->id() } );

$user->commit;

exit 0;

sub create_cookie {
        my $name = shift;
        my $value = shift;

        my $cookie = new CGI::Cookie(
                -name => $name,
                -value => $value,
                -expires =>  '+1M',
                -secure => get_service('config')->file->{session}->{'ssl'},
#                -samesite => "Lax",
        );
        return $cookie;
}

