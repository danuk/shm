use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

my $user = SHM->new( user_id => 40092 );
$user->set_settings({ telegram => { chat_id => 123 } });

no warnings qw(redefine);
no warnings 'once';
*Core::Transport::Telegram::shmEcho = sub { shift; \@_ };

my $template = $user->srv('template');

my $tpl = qq(
<% SWITCH cmd %>
<% CASE '/task' %>
{
    "shmEcho": {
        "task": "{{ task.foo }}"
    }
}
<% CASE '/args' %>
{
    "shmEcho": {
        "param": "{{ args.1 }}"
    }
}
<% END %>
);

my $template_bot_id = $template->_add(
    id => '_bot',
    data => $tpl,
);

subtest 'Test telegram.bot() with task' => sub {
    my $template_id = $template->_add(
        id => '_telegram_bot_task',
        data => '{{ toJson(telegram.bot("_bot","/task")) }}',
    );

    my $template_bot_task = $template->id( $template_id );

    my $ret = $template_bot_task->parse( task => { foo => 2 } );

    is $ret, '[["task","2"]]';
};

subtest 'Test telegram.bot() with args' => sub {
    my $template_id = $template->_add(
        id => '_telegram_bot_args',
        data => '{{ toJson(telegram.bot("_bot","/args",[5,8])) }}',
    );

    my $template_tg = $template->id( $template_id );

    my $ret = $template_tg->parse();

    is $ret, '[["param","8"]]';
};

done_testing();
