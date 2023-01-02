use v5.14;
use warnings;
use utf8;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Utils qw(
    is_email
);

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $mail = get_service('Transport::Mail');

my $ret = $mail->send_mail(
    host => '127.0.0.1',
    from => 'mail@domain.ru',
    to => 'test@domain.ru',
    subject => 'Test subject',
    message => 'example message',
);

is 1,1;

is( is_email('test@server.ru'), 'test@server.ru' );
is( is_email('server.ru'), undef );
is( is_email('<test>test@server.ru'), undef );


done_testing();

