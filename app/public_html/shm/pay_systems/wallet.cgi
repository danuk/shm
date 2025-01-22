#!/usr/bin/perl

# https://docs.wallet.tg/pay/#tag/Order/operation/create
# https://docs.wallet.tg/pay/#operation/completedOrder

use v5.14;
use Core::Base;
use LWP::UserAgent ();
use Core::Utils qw(
    passgen
    encode_json_utf8
    decode_json
);
use MIME::Base64;
use Digest::SHA qw(hmac_sha256_base64);
use CGI;
our $cgi = CGI->new;

use SHM qw(:all);
our %vars = parse_args();

if ( $vars{action} eq 'create' ) {
    my $user;
    if ( $vars{user_id} ) {
        $user = SHM->new( user_id => $vars{user_id} );

        if ( $vars{message_id} ) {
            get_service('Transport::Telegram')->deleteMessage( message_id => $vars{message_id} );
        }

    } else {
        $user = SHM->new();
    }

    my $config = get_service('config', _id => 'pay_systems');
    my $api_key =        $config->get_data->{wallet}->{api_key};
    my $description =    $config->get_data->{wallet}->{description};
    my $failReturnUrl =     $config->get_data->{wallet}->{failReturnUrl};
    my $returnUrl =     $config->get_data->{wallet}->{returnUrl};
    my $autoConversionCurrency =     $config->get_data->{wallet}->{autoConversionCurrency};
    my $currencyCode = $config->get_data->{wallet}->{currencyCode};

    $description ||= $vars{description};

    print_json({ status => 400, msg => 'Error: api_key required. Please set it in config' }) unless $api_key;
    print_json({ status => 400, msg => 'Error: description required. Please set it in config' }) unless $description;
    exit 0 unless( $api_key && $description );
    $vars{amount} ||= 100;

    my $user_chat_id = $user->get_settings->{telegram}->{chat_id};

    my $browser = LWP::UserAgent->new( timeout => 10 );

    my $req =  HTTP::Request->new( POST => "https://pay.wallet.tg/wpay/store-api/v1/order");
    $req->header('Content-type' => 'application/json');
    $req->header('Wpay-Store-Api-Key' => $api_key );
    $req->header('User-Agent' => 'SHM');
    $req->content( encode_json_utf8(
        {
            amount => {
                currencyCode => $currencyCode,
                amount => $vars{amount},
            },
            autoConversionCurrency => $autoConversionCurrency,
            description => sprintf("%s [%d]", $description, $user->id ),
            returnUrl => $returnUrl || 'https://t.me/wallet',
            failReturnUrl => $failReturnUrl || 'https://t.me/wallet',
            externalId => sprintf("ORD-%d-%s", time, passgen(5) ),
            timeoutSeconds => 10800,
            customerTelegramUserId => $user_chat_id,
            customData => $user->id,
        }
    ));
    my $response = $browser->request( $req );

    logger->dump( $response->request );
    logger->dump( $response->content );

    if ( $response->is_success ) {
        my $response_data = decode_json( $response->decoded_content );
        if ( my $location = $response_data->{data}->{directPayLink} ) {
            print_header(
                location => $location,
                status => 301,
            );
        } else {
            print_json( { status => 200, msg => "Payment successful" } );
        }
    } else {
        print_header( status => $response->code );
        print $response->content;
    }
    exit 0;
}

unless ( $vars{DATA}->[0]->{payload} ) {
    print_json({ status => 400, msg => 'Error: bad request' });
    exit 0;
}

my $user = SHM->new( skip_check_auth => 1 );

my $config = get_service('config', _id => 'pay_systems');
my $api_key = $config->get_data->{wallet}->{api_key};
unless ( $api_key ) {
    print_json( { status => 400, msg => 'Error: api_key not exists' } );
    exit 0;
}

my $body = $cgi->param('POSTDATA');
my $method = $ENV{'REQUEST_METHOD'};
my $uri_path = $ENV{'REQUEST_URI'};

my $timestamp = $cgi->http('Walletpay-Timestamp');
my $wp_signature = $cgi->http('Walletpay-Signature');

my $encoded_body = encode_base64($body, '');
my $string = "$method.$uri_path.$timestamp.$encoded_body";

my $hmac = hmac_sha256_base64($string, $api_key);
$hmac .= '=' while length( $hmac ) % 4;

if ( $wp_signature ne $hmac ) {
    print_json({ status => 400, msg => 'Error: bad request' });
    logger->error( "Signature doesn't match" );
    exit 0;
}

if ( $vars{DATA}->[0]->{type} ne 'ORDER_PAID' ) {
    print_json( { status => 200, msg => 'unknown event', event => $vars{type} } );
    exit 0;
}

my $user_id = $vars{DATA}->[0]->{payload}->{customData};
my $amount = $vars{DATA}->[0]->{payload}->{orderAmount}->{amount};

unless ( $user = $user->id( $user_id ) ) {
    print_json( { status => 404, msg => "User [$user_id] not found" } );
    exit 0;
}

unless ( $user->lock( timeout => 10 )) {
    print_json( { status => 408, msg => "The service is locked. Try again later" } );
    exit 0;
}

$user->payment(
    user_id => $user_id,
    money => $amount,
    pay_system_id => 'wallet',
    comment => \%vars,
    uniq_key => $vars{DATA}->[0]->{payload}->{externalId},
);

$user->commit;

print_json( { status => 200, msg => "payment succesfull" } );

exit 0;
