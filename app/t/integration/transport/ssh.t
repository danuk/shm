use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $ssh = get_service('Transport::Ssh');

is( Core::Transport::Ssh::get_ssh_host('127.0.0.1'), 'root@127.0.0.1');
is( Core::Transport::Ssh::get_ssh_host('user@127.0.0.1'), 'user@127.0.0.1');
is( Core::Transport::Ssh::get_ssh_host('server.ru'), 'root@server.ru');
is( Core::Transport::Ssh::get_ssh_host('user@server.ru'), 'user@server.ru');

is( Core::Transport::Ssh::get_ssh_host('127.0.0.300'), undef);
is( Core::Transport::Ssh::get_ssh_host('server'), undef);
is( Core::Transport::Ssh::get_ssh_host('server@'), undef);
is( Core::Transport::Ssh::get_ssh_host('user@'), undef);
is( Core::Transport::Ssh::get_ssh_host('user@server'), undef);
is( Core::Transport::Ssh::get_ssh_host('server.a'), undef);


done_testing();

