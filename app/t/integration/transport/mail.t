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

subtest 'base64 body uses MIME line wrapping' => sub {
    my $captured_body;

    {
        no warnings 'redefine';
        no warnings 'once';
        local *Email::Simple::create = sub {
            my ( $class, %args ) = @_;
            $captured_body = $args{body};
            return bless {}, $class;
        };

        $mail->send_mail(
            host => '127.0.0.1',
            from => 'mail@domain.ru',
            to => 'test@domain.ru',
            subject => 'Long body test',
            message => ('a' x 120),
        );
    }

    ok( defined $captured_body, 'Body captured from Email::Simple::create' );
    like( $captured_body, qr/\n/, 'Base64 body contains MIME line breaks' );

    my ($first_line) = split /\n/, $captured_body;
    ok( length($first_line) <= 76, 'First base64 line length is at most 76 characters' );
};

is( is_email('test@server.ru'), 'test@server.ru' );
is( is_email('server.ru'), undef );
is( is_email('<test>test@server.ru'), undef );


done_testing();

