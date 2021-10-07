#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Router::Simple;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
    decode_json
);

use Data::Dumper;

our %in = parse_args();
$in{filter} = decode_json( $in{filter} ) if $in{filter};

my $routes = {
'/user' => {
    GET => {
        controller => 'User',
    },
},
'/user/passwd' => {
    POST => {
        controller => 'User',
        method => 'api_passwd',
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
'/user/pays/forecast' => {
    GET => {
        controller => 'Pay',
        method => 'forecast',
    },
},
'/services' => {
    GET => {
        controller => 'Service',
        method => 'api_price_list',
    },
},
'/services/:service_id' => {
    GET => {
        controller => 'Service',
        method => 'list_for_api',
    },
},
'/template/:name' => {
    GET => {
        controller => 'Template',
        method => 'template_by_name',
    },
},

'/admin/user/:user_id' => {
    GET => {
        controller => 'User',
        method => 'list_for_api',
        admin => 1,
    },
},
'/admin/user/:user_id/payment' => {
    PUT => {
        controller => 'User',
        method => 'payment',
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

if ( $uri =~/^\/admin\// && !$user->is_admin ) {
    print_header( status => 403 );
    print_json( { error => "Permission denied"} );
    exit 0;
}

if ( my $p = $router->match( sprintf("%s:%s", $ENV{REQUEST_METHOD}, $uri )) ) {

    my $service = get_service( $p->{controller} );
    unless ( $service ) {
        print_header( status => 500 );
        print_json( { error => 'Error'} );
        exit 0;
    }

    my $method = $p->{method} || 'list_for_api';
    unless ( $service->can( $method ) ) {
        print_header( status => 500 );
        print_json( { error => 'Method not exists'} );
    }

    my @ret = $service->$method( %in, %{ $p } );

    my $report = get_service('report');
    unless ( $report->is_success ) {
        print_header( status => 400 );
        print_json( { error => $report->errors } );
        exit 0;
    }

    my $res = \@ret;;
    if ( $ENV{REQUEST_METHOD} eq 'GET' ) {
        $res = {
            items => $service->found_rows(),
            limit => $in{limit} || 25,
            offset => $in{offset} || 0,
            data => \@ret,
        };
    }

    print_header( status => 200 );
    print_json( $res );

} else {
    print_header( status => 404 );
    print_json( { error => 'Method not found'} );
}

$user->commit();

exit 0;

