use v5.14;
use utf8;
use open ':std', ':encoding(UTF-8)';

use Test::More;
use Core::Transport::Mail;

# Gmail отклоняет письма без Message-ID (550 5.7.1, RFC 5322)

my $id = Core::Transport::Mail::message_id('noreply@example.com');
like $id, qr/^<\d+\.\d+\.[0-9a-f]{16}\@example\.com>$/, 'формат <время.pid.случайное@домен отправителя>';

isnt Core::Transport::Mail::message_id('noreply@example.com'), $id, 'каждый раз новый';

like Core::Transport::Mail::message_id(''), qr/^<[^@<>]+\@localhost>$/, 'без адреса и без настроек SHM — localhost';
like Core::Transport::Mail::message_id('SHM <noreply@mail.example.org>'), qr/\@mail\.example\.org>$/, 'домен из адреса с именем';

done_testing();
