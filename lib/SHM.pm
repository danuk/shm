package SHM;

# Secure Hosting Manager - Library (HTTP version)
# Written by DaNuk (DNk) 22/07/2016
# mail@danuk.ru
use v5.14;
use Carp qw(confess);

use CGI;
use CGI::Cookie;
use Session;
use JSON;

use Core::System::ServiceManager qw( get_service );
use Core::Sql::Data;
use Scalar::Util qw(blessed);
use Core::Utils qw(force_numbers);

use base qw(Exporter);

our @EXPORT_OK = qw[
    validate_session
    print_json
    trim
    print_header
    parse_args
    get_service
    blessed
];

our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

my $dbh;
my $dbh_main;
my $bhm;
my $is_header = 0;
my $admin = 0;
my $user_id;
my $real_user_id;
my $cgi = CGI->new;
my %in;


sub new {
    my $class = shift;

    if ( $ENV{REQUEST_METHOD} eq 'OPTIONS' ) {
        print_header(
            'Access-Control-Allow-Origin' => $ENV{HTTP_ORIGIN},
            'Access-Control-Allow-Credentials' => 'true',
            'Access-Control-Allow-Headers' => 'Origin, X-Requested-With, Content-Type, Accept, Authorization',
            'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS, HEAD',
            'Vary' => 'Origin',
            'status' => 204,
        );
        exit 0;
    }

    my $args = {
        user_id => undef,
        skip_check_auth => undef,
        @_,
    };

    $args->{user_id} ||= $ENV{USER_ID};

    # Connect to db
    my $config = get_service('config');
    my $dbh = Core::Sql::Data::db_connect( %{ $config->global->{database} } );
    $config->local('dbh', $dbh );

    my $user_id;

    if ( $args->{user_id} ) {
        $user_id = $args->{user_id};
    } elsif ( !$args->{skip_check_auth} ) {
        my $session = validate_session();
        print_not_authorized() unless $session;
        $user_id = $session->get('user_id');
    }

    $config->local('user_id', $user_id );
    my $user = get_service('user');
    unless ( $user ) {
        print_not_authorized();
    }

    if ($0=~/\/(admin)\// && $user->get_gid != 1 ) {
            print_header( status => 403 );
            print_json( { status => 403, msg => 'Forbidden' } );
            exit 0;
    }

    return $user;
}


sub validate_session {
    my $update_time = shift || 1;

    # Check session
    my %cookies = fetch CGI::Cookie;
    return undef if not exists $cookies{session_id};

    my $session_id = $cookies{session_id}->value;

    my $session = new Session $session_id, %{ get_service('config')->get('session') };
    return undef if not defined($session);

    my $ip = $session->get('ip');
    return undef if $ip ne $ENV{REMOTE_ADDR};

    #$admin = 1 if $session->get('admin');

    $session->set(time => time()) if $update_time;

    return $session;
}

sub print_not_authorized {
    print_header( status => 401 );
    print_json( { status => 401, msg=> "Not authorized" } );
    exit 0;
}

sub print_header {
    return if $is_header;

    my %params = (
        status => 200,
        type => 'application/json',
        charset => 'utf8',
        cookie => undef,
        'Access-Control-Allow-Origin' => $ENV{HTTP_ORIGIN},
        'Access-Control-Allow-Credentials' => 'true',
        @_,
    );

    print $cgi->header( map +( "-$_" => $params{$_} ), grep $params{$_}, keys %params );
    $is_header = 1;
}

sub parse_args {
    use Core::Utils;
    return Core::Utils::parse_args();
}

sub trim { my $str = shift; $str=~s/^\s+|\s+$//g; $str };

sub print_json {
    my $ref = shift || [];
    my %args = (
        @_,
    );

    die 'WTF? blessed object' if blessed $ref;

    # if $ref contained 'status' set to header
    print_header( ref $ref eq 'HASH' ? %{ $ref } : () ) unless $is_header;

    if ( ref $ref eq 'HASH' && $ref->{status} && $ref->{status}!~/^2/ ) {
        if ( my @errors = get_service('report')->errors ) {
            $ref->{errors} = \@errors;
        }
    };

    my $json = new JSON;
    $json->canonical( 1 );
    $json->pretty( 1 ) if $ENV{DEBUG};

    say $json->canonical->encode( force_numbers( $ref ) );
}

1;



