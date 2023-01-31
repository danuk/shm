package SHM;

# Secure Hosting Manager - Library (HTTP version)
# Written by DaNuk (DNk) 22/07/2016
# mail@danuk.ru
use v5.14;
use Carp qw(confess);
use CGI::Carp qw(fatalsToBrowser);

use CGI;
use JSON qw//;
use MIME::Base64;

use Core::System::ServiceManager qw( get_service );
use Core::Sql::Data;
use Scalar::Util qw(blessed);
use Core::Utils qw(
    force_numbers
    switch_user
    parse_headers
    get_cookies
);

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

    # Redirect logs to PIPE
    open STDERR, ">>/tmp/shm_log" if -p "/tmp/shm_log";

    if ( $ENV{REQUEST_METHOD} eq 'OPTIONS' ) {
        print_header(
            'Access-Control-Allow-Origin' => "$ENV{HTTP_ORIGIN}",
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

    my $user_id;
    my %headers = parse_headers;

    if ( $headers{HTTP_TEST} ) {
        $ENV{SHM_TEST} = 1;
    }

    db_connect;

    if ( $args->{skip_check_auth} ) {
        return get_service('user')
    } elsif ( $args->{user_id} ) {
        $user_id = $args->{user_id};
    } elsif ( $ENV{HTTP_AUTHORIZATION} ) {
        my $auth = $ENV{HTTP_AUTHORIZATION};
        $auth =~s/^Basic\s+//;
        $auth = decode_base64( $auth );
        my ( $user, $password ) = split(/\:/, $auth);
        $user_id = ext_user_auth( $user, $password );
    } elsif ( $headers{HTTP_LOGIN} && $headers{HTTP_PASSWORD} ) {
        $user_id = ext_user_auth($headers{HTTP_LOGIN}, $headers{HTTP_PASSWORD});
    } elsif ( !$args->{skip_check_auth} ) {
        my %in = parse_args();
        my $session = validate_session( session_id => $headers{HTTP_SESSION_ID} || $in{session_id} );
        print_not_authorized() unless $session;
        $user_id = $session->user_id;
    }

    unless ( $args->{skip_check_auth} || $user_id ) {
        print_header( status => 400 );
        print_json( { status => 400, msg => 'User not found' } );
        exit 0;
    }

    # Store current user_id to local config
    switch_user( $user_id );

    my $user = get_service('user');

    if ($ENV{SCRIPT_NAME}=~/\/admin\// && !$user->is_admin ) {
        print_header( status => 403 );
        print_json( { status => 403, msg => 'Forbidden' } );
        exit 0;
    }

    return $user;
}

sub ext_user_auth {
    my ($login, $password) = @_;

    db_connect();
    my $user = get_service('user');
    $user = $user->auth(
        login => $login,
        password => $password,
    );
    unless ( $user ) {
        print_json( { status => 401, msg => 'Incorrect login or password' } );
        exit 0;
    }
    return $user->id;
}

sub db_connect {
    my $config = get_service('config');

    # Connect to db
    my $dbh = Core::Sql::Data::db_connect( %{ $config->file->{config}{database} } );

    unless ( $dbh ) {
        print_header( status => 503 );
        print_json( { status => 503, msg => "Can't connect to DB" } );
        exit 0;
    }

    $config->local('dbh', $dbh );
}

sub validate_session {
    my %args = (
        session_id => undef,
        @_,
    );

    my $session_id = $args{session_id};

    unless ( $session_id ) {
        $session_id = get_cookies('session_id');
        return undef unless $session_id;
    }

    my $session = get_service('sessions')->validate(
        session_id => $session_id,
    );
    return undef unless $session;

    return $session;
}

sub print_not_authorized {
    print_header( status => 401 );
    print_json( { status => 401, msg=> "Not authorized" } );
    exit 0;
}

sub print_header {
    my %args = (
        status => 200,
        type => 'application/json',
        charset => 'utf8',
        'Access-Control-Allow-Origin' => "$ENV{HTTP_ORIGIN}",
        'Access-Control-Allow-Credentials' => 'true',
        @_,
    );

    return undef if $is_header;

    print $cgi->header( map +( "-$_" => $args{$_} ), keys %args );
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
    $json->latin1( 1 );
    $json->pretty( 1 ) if $ENV{DEBUG};

    say $json->canonical->encode( force_numbers( $ref ) );
}

sub DESTROY {
    my $dbh = get_service('config')->local->{dbh};
    $dbh->disconnect if $dbh;
}

1;



