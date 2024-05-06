#!/usr/bin/perl

# https://help.crypt.bot/crypto-pay-api#createInvoice
# https://help.crypt.bot/crypto-pay-api#webhooks

use v5.14;
use Core::Base;
use LWP::UserAgent ();
use Digest::SHA qw(sha256 hmac_sha256_hex);
use Core::Utils qw(
    decode_json
);

use SHM qw(:all);
our %vars = parse_args();

use CGI;
our $cgi = CGI->new;

if ( $vars{action} eq 'create' ) {
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
    my $api_key =        $config->get_data->{cryptopay}->{api_key};
    my $description =    $config->get_data->{cryptopay}->{description};
    my $paid_btn_url =    $config->get_data->{cryptopay}->{paid_btn_url};
    my $paid_btn_name =    $config->get_data->{cryptopay}->{paid_btn_name};
    my $fiat =    $config->get_data->{cryptopay}->{fiat};

    $description ||= $vars{description};

    print_json({ status => 400, msg => 'Error: api_key required. Please set it in config' }) unless $api_key;
    print_json({ status => 400, msg => 'Error: description required. Please set it in config' }) unless $fiat;
    exit 0 unless( $api_key && $fiat );
    $vars{amount} ||= 100;

    my $browser = LWP::UserAgent->new( timeout => 10 );
    $browser->default_header('Crypto-Pay-API-Token' => $api_key, 'User-Agent' => 'SHM');

    my $response = $browser->post('https://pay.crypt.bot/api/createInvoice',
        Content => {
            amount =>  $vars{amount},
            currency_type => "fiat",
            fiat => $fiat,
            description => sprintf("%s [%d]", $description, $user->id ),
            paid_btn_name => $paid_btn_name || "openBot",
            paid_btn_url => $paid_btn_url || 'https://t.me/send',
            allow_comments => "false",
        },
    );

    if ( $response->is_success ) {
        my $response_data = decode_json( $response->decoded_content );
        print_header(
            location => $response_data->{result}->{bot_invoice_url},
            status => 301,
        );
    } else {
        print_json({
                status => 503,
                decoded_content => $response->decoded_content,
                status_line => $response->status_line,
        });
    }

    exit 0;
}

my $user = SHM->new( skip_check_auth => 1 );

my $config = get_service('config', _id => 'pay_systems');
my $api_key = $config->get_data->{cryptopay}->{api_key};
unless ( $api_key ) {
    print_json( { status => 400, msg => 'Error: api_key not exists' } );
    exit 0;
}

my $secret = sha256($api_key);
my $body = $cgi->param('POSTDATA');
my $digest = hmac_sha256_hex($body, $secret);
my $signature = $cgi->http('Crypto-Pay-Api-Signature');

if ($signature ne $digest) {
    print_json( { status => 400, msg => "Error: Signature doesn't match" } );
    exit 0;
}

unless ( $vars{payload} ) {
    print_json({ status => 400, msg => 'Error: bad request' });
    exit 0;
}

if ( $vars{payload}->{status} ne 'paid' ) {
    print_json( { status => 200, msg => 'unknown event', event => $vars{payload}->{status} } );
    exit 0;
}

my $user_id;

if ($vars{payload}->{description} =~ /\[(.*?)\]/) {
    $user_id = $1;
}

my $amount = $vars{payload}->{amount};

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
    pay_system_id => 'CryptoPay',
    comment => \%vars,
    uniq_key => $vars{payload}->{hash},
);

$user->commit;

print_json( { status => 200, msg => "payment succesfull" } );

exit 0;
