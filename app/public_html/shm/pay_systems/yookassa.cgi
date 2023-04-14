#!/usr/bin/perl

# https://yookassa.ru/developers/api#create_payment
# https://yookassa.ru/developers/using-api/webhooks#using

use v5.14;
use Core::Base;
use LWP::UserAgent ();
use Core::Utils qw(
    passgen
    encode_json
    decode_json
);

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
    my $api_key =    $config->get_data->{yookassa}->{api_key};
    my $account_id = $config->get_data->{yookassa}->{account_id};
    my $return_url = $config->get_data->{yookassa}->{return_url};

    print_json({ status => 400, msg => 'Error: api_key required. Please set it in config' }) unless $api_key;
    print_json({ status => 400, msg => 'Error: account_id required. Please set it in config' }) unless $account_id;
    exit 0 unless( $api_key && $account_id );

    my $ua = LWP::UserAgent->new( timeout => 10 );

    my $content = encode_json({
        amount => {
            value => $vars{amount} || 100,
            currency => "RUB",
        },
        description => $user->id,
        confirmation => {
            type => "redirect",
            return_url => $return_url || 'https://www.example.com',
        },
        capture => "true",
    });

    my $browser = LWP::UserAgent->new;
    my $req =  HTTP::Request->new( POST => "https://api.yookassa.ru/v3/payments");
    $req->header('content-type' => 'application/json');
    $req->header('Idempotence-Key' => passgen(30) );
    $req->authorization_basic( $account_id, $api_key );
    $req->content( $content );
    my $response = $browser->request( $req );

    logger->dump( $response->request );

    if ( $response->is_success ) {
        my $response_data = decode_json( $response->decoded_content );
        print_header(
            location => $response_data->{confirmation}->{confirmation_url},
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
my $account_id = $config->get_data->{yookassa}->{account_id};
print_json({ status => 400, msg => 'Error: account_id required. Please set it in config' }) unless $account_id;

if ( $vars{event} ne 'payment.succeeded' ) {
    print_json( { status => 200, msg => 'unknown event' } );
    exit 0;
}

if ( $vars{object}->{status} ne 'succeeded' ||
     $vars{object}->{recipient}->{account_id} != $account_id ||
     $vars{object}->{paid} != 1,
    !$vars{object}->{description}
) {
    logger->error('Incorrect input data');
    logger->dump( \%vars );
    print_json( { status => 200, msg => 'For more details see logs' } );
    exit 0;
}

my $user_id = $vars{object}->{description};
my $amount = $vars{object}->{amount}->{value};

unless ( $user_id ) {
    print_json( { status => 400, msg => 'User (description) required' } );
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
    user_id => $user_id,
    money => $amount,
    pay_system_id => $vars{object}->{test} ? 'yookassa-test' : 'yookassa',
    comment => \%vars,
);

$user->commit;

print_json( { status => 200, msg => "Payment successful" } );

exit 0;

