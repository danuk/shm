#!/usr/bin/perl

# https://docs.freekassa.com/#section/2.-Vvedenie
# http://127.0.0.1:8081/shm/pay_systems/freekassa.cgi?action=create&amount=100&t=1

use CGI::Carp qw(fatalsToBrowser);
use v5.14;
use Core::Base;
use LWP::UserAgent ();
use URI;
use URI::QueryParam;
use Digest::SHA qw(sha1_hex);
use Digest::MD5 qw(md5_hex);

use SHM qw(:all);
our %vars = parse_args();
$vars{amount} ||= 100;

for ( keys %vars ) {
    $vars{ lc $_ } = delete $vars{ $_ };
}

if ( $vars{action} eq 'create' && $vars{amount} ) {
    my $user;
    if ( $vars{user_id} ) {
        $user = SHM->new( user_id => $vars{user_id} );
        unless ( $user ) {
            print_json({ status => 400, msg => 'Error: unknown user' });
            exit 0;
        }

        if ( $vars{message_id} ) {
            get_service('Transport::Telegram')->deleteMessage( message_id => $vars{message_id} );
        }
    } else {
        $user = SHM->new();
    }

    my $config = get_service('config', _id => 'pay_systems');
    unless ( $config ) {
        print_json( { status => 400, msg => 'Error: config pay_systems->freekassa not exists' } );
        exit 0;
    }

    my $settings = $config->get_data->{freekassa};

    my %p = (
        merchant_id => $settings->{merchant_id},
        order_amount => $vars{amount},
        secret_word => $settings->{secret_word_1},
        currency => $settings->{currency} || 'RUB',
        order_id => $user->id,
    );

    for ( sort keys %p ) {
        unless ( $p{ $_ } ) {
            print_json( { status => 400, msg => "Error: param '$_' not present" } );
            exit 0;
        }
    }

    my $sign = md5_hex( join(':', $p{merchant_id}, $p{order_amount}, $p{secret_word}, $p{currency}, $p{order_id} ) );

    my $uri = URI->new( 'https://pay.freekassa.com' );
    $uri->query_param_append( 'm', $p{merchant_id} );
    $uri->query_param_append( 'oa', $p{order_amount} );
    $uri->query_param_append( 'us_user_id', $user->id );
    $uri->query_param_append( 'currency', $p{currency} );
    $uri->query_param_append( 'o', $p{order_id} );
    $uri->query_param_append( 's', $sign );
    my $url = $uri->as_string;

    print_header(
        location => $url,
        status => 301,
    );
    exit 0;
}

my $user = SHM->new( skip_check_auth => 1 );

if ( $vars{status_check} ) {
    $user->payment(
        user_id => 1,
        money => 0,
        pay_system_id => 'freekassa-test',
        comment => \%vars,
    );
    $user->commit;
    print_json( { status => 200,  msg => 'Test OK' } );
    exit 0;
}

my $config = get_service('config', _id => 'pay_systems');
unless ( $config ) {
    print_json( { status => 400, msg => 'Error: config pay_systems not exists' } );
    exit 0;
}

my $settings = $config->get_data->{freekassa};

if ( $settings->{secret_word_2} ) {
    my $sign = md5_hex( join(':',
        $settings->{merchant_id},
        $vars{amount},
        $settings->{secret_word_2},
        $vars{merchant_order_id},
    ));

    if ( $sign ne $vars{sign} ) {
        print_json( { status => 400, msg => 'Error: incorrect signature' } );
        exit 0;
    }
}

my $user_id = $vars{us_user_id};
unless ( $user_id ) {
    print_json( { status => 400, msg => 'User id required' } );
    exit 0;
}

unless ( $user = $user->id( $user_id ) ) {
    print_json( { status => 404, msg => "User [$user_id] not found" } );
    exit 0;
}

unless ( $user->lock( timeout => 10 )) {
    print_json( { status => 408, msg => "The service is locked. Try again later" } );
    exit 0;
}

$user->payment(
    user_id => $user->id,
    money => $vars{amount} || 0,
    pay_system_id => 'freekassa',
    comment => \%vars,
);

$user->commit;

print_header( status => 200, type => 'text/html' );
print "YES";

exit 0;

