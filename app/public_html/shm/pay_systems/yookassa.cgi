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
    get_random_value
);

use SHM qw(:all);
our %vars = parse_args();

if ( $vars{action} eq 'create' || $vars{action} eq 'payment' ) {
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
    my $api_key =        $config->get_data->{yookassa}->{api_key};
    my $account_id =     $config->get_data->{yookassa}->{account_id};
    my $return_url =     $config->get_data->{yookassa}->{return_url};
    my $description =    get_random_value( $vars{description} || $config->get_data->{yookassa}->{description} );
    my $customer_email = $vars{email} || $config->get_data->{yookassa}->{customer_email};
    my $save_payments  = $config->get_data->{yookassa}->{save_payments};

    print_json({ status => 400, msg => 'Error: api_key required. Please set it in config' }) unless $api_key;
    print_json({ status => 400, msg => 'Error: account_id required. Please set it in config' }) unless $account_id;
    print_json({ status => 400, msg => 'Error: description required. Please set it in config' }) unless $description;
    print_json({ status => 400, msg => 'Error: customer_email required. Please set it in config' }) unless $customer_email;
    exit 0 unless( $api_key && $account_id && $description && $customer_email );

    my $ua = LWP::UserAgent->new( timeout => 10 );

    $vars{amount} ||= 100;

    my $payment_method_id;

    if ( $vars{action} eq 'payment' ) {
        $payment_method_id = $user->get_settings->{pay_systems}->{yookassa}->{payment_id};
    }

    my $receipt = {
        customer => {
            email => $customer_email,
        },
        items => [
            {
                description => $description,
                quantity => 1,
                amount => {
                    value => $vars{amount},
                    currency => "RUB",
                },
                vat_code => "1",
                payment_mode => "full_payment",
                payment_subject => "service",
            },
        ],
    };

    my $content = encode_json({
        metadata => {
            user_id => $user->id,
        },
        amount => {
            value => $vars{amount},
            currency => "RUB",
        },
        capture => "true",
        description => sprintf("%s [%d]", $description, $user->id ),
        $payment_method_id ? (
            payment_method_id => $payment_method_id,
        ) : (
            $save_payments ? ( save_payment_method => "true" ) : (),
            confirmation => {
                type => "redirect",
                return_url => $return_url || 'https://www.example.com',
            },
        ),
        receipt => $receipt,
    });

    my $browser = LWP::UserAgent->new;
    my $req =  HTTP::Request->new( POST => "https://api.yookassa.ru/v3/payments");
    $req->header('content-type' => 'application/json');
    $req->header('Idempotence-Key' => passgen(30) );
    $req->authorization_basic( $account_id, $api_key );
    $req->content( $content );
    my $response = $browser->request( $req );

    logger->dump( $response->request );
    logger->dump( $response->content );

    if ( $response->is_success ) {
        my $response_data = decode_json( $response->decoded_content );
        if ( my $location = $response_data->{confirmation}->{confirmation_url} ) {
            print_header(
                location => $location,
                status => 301,
            );
        } else {
            if ( $response_data->{status} eq 'succeeded' ) {
                print_json( { status => 200, msg => "Payment successful" } );
            } else {
                my %i16n_ru = (
                    insufficient_funds => 'недостаточно средств',
                    permission_revoked => 'автосписания запрещены',
                );

                my $reason = $response_data->{cancellation_details}->{reason};

                if ( $reason ) {
                    print_json({
                        status => 406,
                        msg => $reason,
                        exists $i16n_ru{ $reason } ? ( msg_ru => $i16n_ru{ $reason } ) : (),
                    });
                } else {
                    print_json( { status => 406 } );
                }
            }
        }
    } else {
        print_header( status => 402 );
        print $response->content;
    }
    exit 0;
}

my $user = SHM->new( skip_check_auth => 1 );

unless ( $vars{object} ) {
    print_json({ status => 400, msg => 'Error: bad request' });
    exit;
}

my $config = get_service('config', _id => 'pay_systems');
my $account_id = $config->get_data->{yookassa}->{account_id};
print_json({ status => 400, msg => 'Error: account_id required. Please set it in config' }) unless $account_id;


my %allowed_events = (
    'payment.succeeded' => 1,
    'refund.succeeded' => 1,
    'payment.canceled' => 1,
);

unless ( exists $allowed_events{ $vars{event} } ) {
    print_json( { status => 200, msg => 'unknown event', event => $vars{event} } );
    exit 0;
}

if (    $vars{event} ne 'refund.succeeded' &&
        $vars{object}->{recipient}->{account_id} != $account_id
    ) {
    logger->error('Incorrect input data');
    logger->dump( \%vars );
    print_json( { status => 200, msg => 'Error: for more details see logs' } );
    exit 0;
}

my $user_id = $vars{object}->{metadata}->{user_id};
my $amount = $vars{object}->{amount}->{value};

if ( $vars{event} eq 'refund.succeeded' ) {
    # Try to determine the user_id from previous transactions
    my ($pay) = get_service('pay')->_list( where => {
        uniq_key => $vars{object}->{payment_id},
    });

    $user_id = $pay->{user_id} if $pay;
}

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

if ( $vars{object}->{payment_method}->{saved} ) {
    $user->set_settings({
        pay_systems => {
            yookassa => {
                name => $vars{object}->{payment_method}->{title},
                payment_id => $vars{object}->{payment_method}->{id},
            },
        },
    });
}

my $uniq_key = $vars{object}->{id};

my $ps_name = 'yookassa';

if ( $vars{event} eq 'payment.canceled' ) {
    $ps_name .= '-canceled';
    $uniq_key = sprintf("canceled-%s", $vars{object}->{id} );
    $amount = 0;
}

if ( $vars{event} eq 'refund.succeeded' ) {
    $ps_name .= '-refund';
    $uniq_key = sprintf("refund-%s", $vars{object}->{payment_id} );
    $amount = -$amount;
}

$ps_name .= '-test' if $vars{object}->{test};

$user->payment(
    user_id => $user_id,
    money => $amount,
    pay_system_id => $ps_name,
    comment => \%vars,
    uniq_key => $uniq_key,
);

$user->commit;

print_json( { status => 200, msg => "operation successful" } );

exit 0;

