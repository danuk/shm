#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Router::Simple;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
);

use Data::Dumper;

our %in = parse_args();

my $routes = {
'/user' => {
    GET => {
        controller => 'User',
    },
},
'/user/services' => {
    GET => {
        controller => 'UserService',
    },
},
'/user/services/:usi' => {
    GET => {
        controller => 'UserService',
    },
},
'/user/withdraws' => {
    GET => {
        controller => 'Withdraw',
    },
},
'/user/pays' => {
    GET => {
        controller => 'Pay',
    },
},
'/services' => {
    GET => {
        controller => 'Service',
        method => 'api_price_list',
    },
},

};

my $router = Router::Simple->new();
for my $uri ( keys %{ $routes } ) {
    for my $method ( keys %{ $routes->{$uri} } ) {
        $router->connect( sprintf("%s:%s", $method, $uri), $routes->{$uri}->{$method} );
    }
}

my $uri = $ENV{SCRIPT_NAME};
$uri =~s/^\/shm\/v\d+//;
$uri =~s/\/$//;

if ( my $p = $router->match( sprintf("%s:%s", $ENV{REQUEST_METHOD}, $uri )) ) {

    my $service = get_service( $p->{controller} );
    unless ( $service ) {
        print_header( status => 500 );
        print_json( { error => 'Error'} );
        exit 0;
    }

    my $m = $p->{method} || 'list_for_api';
    unless ( $service->can( $m ) ) {
        print_header( status => 500 );
        print_json( { error => 'Method not exists'} );
    }

    my @ret = $service->$m( %in, %{ $p } );

    my $report = get_service('report');
    unless ( $report->is_success ) {
        print_header( status => 404 );
        print_json( error => $report->errors );
        exit 0;
    }

    print_header( status => 200 );
    print_json( \@ret );

} else {
    print_header( status => 404 );
    print_json( { error => 'Method not found'} );
}

exit 0;

