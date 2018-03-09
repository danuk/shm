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
my $res = {};
my %in = parse_args();
my $service = get_service('service');

if ( $ENV{REQUEST_METHOD} eq 'PUT' ) {
    my %service = $service->add( %in )->get;
    $res = \%service;
}
elsif ( $ENV{REQUEST_METHOD} eq 'POST' ) {
    $service = $service->id( $in{service_id} );
    $service->set( %in );
    my %data = $service->get;
    $res = \%data;
}    
elsif ( $ENV{REQUEST_METHOD} eq 'DELETE' ) {
    $service = $service->id( $in{service_id} );

    if ( $service ) {
        $service->delete();
        %headers = ( status => 204 );
    } else {
        %headers = ( status => 400 );
    }
}
else {
    my %args;

    if ( $in{parent} ) {
        my $ss = get_service('SubServices');
        my @ss_ids = $ss->_list( where => { service_id => $in{parent} } );
        unless ( @ss_ids ) {
            print_json( [] );
            exit 0;
        }

        $args{where} = { service_id => { -in => [ map $_->{subservice_id}, @ss_ids ] } };
    }

    my @list = $service->_list( %args );
    $res = \@list;

    my $numRows = $user->found_rows;
    %headers = http_content_range( http_limit, count => $numRows );
}

print_header( %headers );
print_json( $res );

exit 0;

