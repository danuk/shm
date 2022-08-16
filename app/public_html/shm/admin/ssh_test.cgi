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

my $parser = get_service('template');
my $cmd = $in{settings}{cmd} || $in{cmd} || 'uname -a';
$cmd = $parser->parse(
    data => $cmd,
    usi => $in{settings}{usi} || $in{usi},
);

my $pipeline_id = get_service('console')->new_pipe;

my (undef, $res ) = $ssh->exec(
    host => $in{host},
    key_id => 1,
    wait => $in{wait} || 0,
    pipeline_id => $pipeline_id,
    %{ $in{settings} || {} },
    cmd => $cmd,
);

print_header();
print_json( $res );


if ( $in{debug} && $in{wait} ) {
    my %ret = get_service('console', _id => $pipeline_id)->reload;
    say "\n\n";
    say "="x100;
    say "$ret{log}";
    say "="x100;
}

$user->commit;

exit 0;

