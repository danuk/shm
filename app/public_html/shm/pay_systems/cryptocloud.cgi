#!/usr/bin/perl

# https://yoomoney.ru/transfer/myservices/http-notification

use v5.14;

use Digest::SHA qw(sha1_hex);
use SHM qw(:all);
my $user = SHM->new( skip_check_auth => 1 );

our %vars = parse_args();

my $user_id = 1;

$user->payment(
    user_id => $user_id,
    money => 0,
    pay_system_id => 'cryptocloud',
    comment => \%vars,
);

print_json( { status => 200, msg => "Payment successful" } );

$user->commit;

exit 0;

