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

my $pipeline_id = get_service('console')->new_pipe;

my (undef, $res ) = $ssh->exec(
    host => 'ssm@127.0.0.1',
    server_id => 1,
    key_id => 1,
    pipeline_id => $pipeline_id,
    event_name => 'test',
    cmd => 'uname -a',
    %{ $in{settings} || {} },
);

$user->commit;

exit 0;

