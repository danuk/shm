#!/usr/bin/perl

use v5.14;

use Digest::SHA qw(sha1_hex);
use SHM qw(:all);
use Core::Utils qw(
    encode_utf8
    decode_json
);

our %vars = parse_args();
$vars{amount} ||= 100;

if ( $vars{action} eq 'create' && $vars{amount} ) {
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
    my $api_key = $config->get_data->{cryptocloud}->{api_key};
    my $shop_id = $config->get_data->{cryptocloud}->{shop_id};

    print_json({ status => 400, msg => 'Error: api_key required. Please set it in config' }) unless $api_key;
    print_json({ status => 400, msg => 'Error: shop_id required. Please set it in config' }) unless $shop_id;
    exit 0 unless( $api_key && $shop_id );

    use LWP::UserAgent ();
    my $ua = LWP::UserAgent->new(timeout => 10);

    $ua->default_header('Authorization' => sprintf("Token %s", $api_key ));

    my $response = $ua->post( 'https://api.cryptocloud.plus/v1/invoice/create',
        Content => encode_utf8({
            shop_id => $shop_id,
            order_id => $user->id,
            amount => $vars{amount},
        }),
    );

    if ( $response->is_success ) {
        my $response_data = decode_json( $response->decoded_content );
        print_header(
            location => $response_data->{pay_url},
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

$user->payment(
    user_id => $vars{order_id} || 1,
    money => $vars{amount_crypto},
    pay_system_id => 'cryptocloud',
    comment => \%vars,
);

print_json( { status => 200, msg => "Payment successful" } );

$user->commit;

exit 0;

