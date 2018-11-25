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
);

my %headers;
our %in = parse_args();
my $res;

unless ( $in{object} ) {
    print_header( status => 400 );
    print_json( { error => "Unknown object" } );
    exit 0;
}

$in{object} =~s/\.\w+$//;
# Convert to lamelcase
$in{object} = join('', map( ucfirst $_, split /_/, $in{object} )); 

my $service_name = $in{object};

our $service = get_service( $service_name );
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
    if ( my $id = $service->add( %in ) ) {
        my %data = $service->id( $id )->get;
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
        %headers = ( status => 400 );
        $res = { error => "Can't delete object" };
    }
}
else {
    my @ret = $service->list_for_api( %in, admin => 1 );
    $res = \@ret;

    my $numRows = $user->found_rows;
    %headers = http_content_range( http_limit, count => $numRows );
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
