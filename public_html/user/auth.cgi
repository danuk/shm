#!/usr/bin/perl

use strict;
use v5.14;

my $cgi = CGI->new;
my %in = $cgi->Vars;

use CGI::Carp qw(fatalsToBrowser);
use Session;

use Core::System::ServiceManager qw( get_service );
my $cfg = get_service('config')->get;

use SHM qw(:all);
my $cli = SHM->new( skip_check_auth => 1 );

my $session = validate_session();
if ($session) {
    print_json( { status => 0, msg => 'Already authorized', session_id => $session->session_id(), user_id => $session->get('user_id')   } );
	exit 0;
}

my $http_agent = $ENV{HTTP_USER_AGENT}; $http_agent=~s/.*\s+//;
my $agent = $in{agent} || $http_agent;

my $client = $cli->search_client( agent => $agent, host => $ENV{SERVER_NAME}, ip => $ENV{REMOTE_ADDR} );
unless ( $client ) {
    print_json( { status => 401, msg => 'client not found', agent => $agent } );
	exit 0;
}

unless ( $in{login} && $in{password} ) {
	print_json( { status => 400, msg => 'login or password not present' } );
	exit 0;
}

unless ( $cli->id( $client->{client_id} )->user->auth( login => trim($in{login}), pass => trim($in{password}) )) {
    print_json( { status => 401, msg => 'Incorrect login or password', agent => $agent } );
	exit 0;
}

my $session = Session->new( undef, %{ $cfg->{session_config} } );
my $session_id = $session->session_id();

$session->set( client_id => $cli->id() );
$session->set( user_id => $cli->user->id() );
$session->set( ip => $ENV{REMOTE_ADDR} );
$session->set( time => time() );

print_header( cookie => create_cookie('session_id',$session_id) );
print_json( { status => 200, msg => 'Successfully', session_id => $session_id, user_id => $cli->user->id() } );

exit 0;

sub create_cookie {
        my $name = shift;
        my $value = shift;

        my $cookie = new CGI::Cookie(
                -name => $name,
                -value => $value,
                -expires =>  '+1M',
                -secure => $cfg->{config}->{'ssl'}
        );
        return $cookie;
}

