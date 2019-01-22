#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
);

our %in = parse_args();
my $ssh = get_service( 'Transport::Ssh' );

my %res = $ssh->exec(
    host => $in{host},
    cmd => 'uname -a',
    %{ $in{params} || () },
);

$res{result} = delete $res{ (keys %res)[0] };

print_header();
print_json( \%res );

exit 0;

