#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
    start_of_month
    http_limit
    http_content_range
    now
    switch_user
);

my %headers;
our %in = parse_args();
delete $in{where};

my $res;
my $admin = 1;

# Switch to user
if ( $in{user_id} ) {
    switch_user( $in{user_id} );
    $admin = 0;
}

unless ( $in{object} ) {
    print_header( status => 400 );
    print_json( { error => "Unknown object" } );
    exit 0;
}

$in{object} =~s/\.\w+$//;
# Convert to lamelcase
$in{object} = join('', map( ucfirst $_, split /_/, $in{object} ));

my $service_name = $in{object};

our $service = get_service( $service_name, ( $in{id} ? ( _id => $in{id} ) : () ) );
unless ( $service ) {
    print_header( status => 400 );
    print_json( { error => "`$service_name` not exists" } );
    exit 0;
}

unless ( $service->can('table') ) {
    print_header( status => 400 );
    print_json( { error => "service not supported API" } );
    exit 0;
}

if ( $ENV{REQUEST_METHOD} eq 'PUT' ) {
    if ( my $ret = $service->add( %in ) ) {
        my %data = ref $ret ? $ret->get : $service->id( $ret )->get;
        $res = \%data;
    }
    else {
        %headers = ( status => 400 );
        $res = { error => "Can't add new object" };
    }
}
elsif ( $ENV{REQUEST_METHOD} eq 'POST' ) {
    $service = $service->id( get_service_id() );
    $service->set( %in );
    my %ret = $service->get;
    $res = \%ret;
}
elsif ( $ENV{REQUEST_METHOD} eq 'DELETE' ) {
    if ( my $obj = $service->id( get_service_id() ) ) {
        $obj->delete();
        %headers = ( status => 204 );
    } else {
        %headers = ( status => 404 );
        $res = { error => "Service not found" };
    }
}
else {
    if ( my $method = $in{method} ) {
        if ( $service->can( $method ) ) {
            $res = $service->$method( %in, admin => $admin );
            if ( !ref $res ) {
                $res = [ $res ];
            }
        }
        else {
            %headers = ( status => 404 );
            $res = { error => "Method not found" };
        }
    } else {
        my @ret = $service->list_for_api( %in, admin => $admin );
        $res = \@ret;
    }

    my $numRows = $service->found_rows;
    %headers = http_content_range( http_limit, count => $numRows );
}

my $report = get_service('report');

unless ( $report->is_success ) {
    %headers = ( status => 400 );
    $res = { error => $report->errors };
}

print_header( %headers );
print_json( $res );

exit 0;

sub get_service_id {
    my $service_id = $in{ $service->get_table_key } || $in{id};

    unless ( $service_id ) {
        print_header( status => 400 );
        print_json( { error => '`id` not present' } );
        exit 0;
    }
    return $service_id;
}
