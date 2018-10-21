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

my $service = get_service('ServicesCommands');
my $service_id = $in{ $service->get_table_key };

if ( $ENV{REQUEST_METHOD} eq 'PUT' ) {
    if ( my $id = $service->add( %in ) ) {
        my %data = $service->id( $id )->get;
        $res = \%data;
    }
    else {
        %headers = ( status => 400 );
    }
}
elsif ( $ENV{REQUEST_METHOD} eq 'POST' ) {
    $service = $service->id( $service_id );
    $service->set( %in );
    my %ret = $service->get;
    $res = \%ret;
}
elsif ( $ENV{REQUEST_METHOD} eq 'DELETE' ) {
    if ( my $obj = $service->id( $service_id ) ) {
        $obj->delete();
        %headers = ( status => 204 );
    } else {
        %headers = ( status => 400 );
    }
}
else {
    my @ret = $service->_list();
    $res = \@ret;

    my $numRows = $user->found_rows;
    %headers = http_content_range( http_limit, count => $numRows );
}

print_header( %headers );
print_json( $res );

exit 0;

