#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
);

our %in = parse_args();

my %args = (
    settings => {
        server_id => $in{server_id},
    },
    event => {
        title => 'test mail',
        kind => 'Transport::Mail',
        method => 'send',
        settings => {
            subject => 'This is test subject from SHM',
            message => 'This is test message from SHM',
            %{ $in{settings} || {} },
        },
    },
);

get_service('Events')->make( %args );

print_header();
print_json( );

$user->commit;

exit 0;

