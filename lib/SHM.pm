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

use base qw(Exporter);

our @EXPORT_OK = qw[
    validate_session
    print_json
    trim
    print_header
    parse_args
];

our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

my %client;
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

    my $args = {
        client_id => undef,
        user_id => undef,
        skip_check_auth => undef,
        @_,
    };

    my $client = get_service('client');

    $args->{client_id} ||= $ENV{CLIENT_ID};
    $args->{user_id} ||= $ENV{USER_ID};

    if ( $args->{client_id} ) {
        confess ("Client not found") unless $client->id( $args->{client_id} );
    }

    if ( $args->{user_id} ) {
        confess ("User not found") unless $client->user->id( $args->{user_id} );
    } elsif ( not $args->{skip_check_auth} ) {

        if ($0=~/\/(admin|spool)\//) {
            print_json( { status => 403, msg => 'Forbidden' } );
            exit 0;
        }
        my $session = validate_session();
        print_not_authorized() unless $session;

        $client->id( $session->get('client_id') )->user->id( $session->get('user_id') );
        print STDERR 'CLIENT_ID: '. $session->get('client_id') . ', USER_ID: ' . $session->get('user_id');
    }
    return $client;
}


sub validate_session {
    my $update_time = shift || 1;

    # Check session
    my %cookies = fetch CGI::Cookie;
    return undef if not exists $cookies{session_id};

    my $session_id = $cookies{session_id}->value;

    my $session = new Session $session_id, %{ get_service('config')->get->{session_config} };
    return undef if not defined($session);

    my $ip = $session->get('ip');
    return undef if $ip ne $ENV{REMOTE_ADDR};

    #$admin = 1 if $session->get('admin');

    $session->set(time => time()) if $update_time;

    return $session;
}

sub print_not_authorized {
    print_header() unless $is_header;
    print_json( { status => 401, msg=> "Not authorized" });
    exit 0;
}

sub print_header {
    return if $is_header;

    my %params = (
        status => 200,
        type => 'application/json',
        charset => 'utf8',
        cookie => undef,
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
    my $sort = shift;

    use Scalar::Util qw(blessed);
    die 'WTF? blessed object' if blessed $ref;

    # if $ref contained 'status' set to header
    print_header( $ref ) unless $is_header;

    if ($sort=~/^(-|\+)?(\w+)$/)
        {
        my @ret = @{$ref};
                my @sort;

        my ($desc, $field) = ($1, $2);
        $desc = $desc eq '-' ? 1 : 0;

        if ($ret[0]->{$field}=~/^\-?\d+(\.\d+)?$/)
        { # numeric sort
            if ($desc) {
                @sort = sort { $b->{$field} <=> $a->{$field} } @ret;
            }
            else
            {
                @sort = sort { $a->{$field} <=> $b->{$field} } @ret;
            }
        }
        else
        {
            if ($desc) {
                @sort = sort { $b->{$field} cmp $a->{$field} } @ret;
            }
            else
            {
                @sort = sort { $a->{$field} cmp $b->{$field} } @ret;
            }
        }
        print to_json(\@sort, $ENV{CBI_MODE} ? undef : {pretty => 1}) . "\n";
    }
    else
    {
        print to_json($ref, $ENV{CBI_MODE} ? undef : {pretty => 1}) . "\n";
    }
    return;
}

1;



