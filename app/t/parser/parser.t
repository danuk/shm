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

my $p = get_service('parser');

is $p->eval_var( "user.id" ), 40092;
is $p->eval_var( "user.user_id" ), 40092;
is $p->eval_var( "user.login" ), 'danuk';

is $p->eval_var( "id", usi => 99 ), 99;
is $p->eval_var( "us.id", usi => 99 ), 99;
is $p->eval_var( "us.user_service_id", usi => 99 ), 99;
is $p->eval_var( "us.status", usi => 99 ), 'ACTIVE';
is $p->eval_var( "us.next", usi => 99 ), 0;
is $p->eval_var( "us.service_id", usi => 99 ), 110;
is $p->eval_var( "us.settings.quota", usi => 99 ), 10000;
is $p->eval_var( "us.settings.quota", usi => 100 ), 46;
is $p->eval_var( "us.settings.unknown", usi => 100 ), '';
is $p->eval_var( "us.settings.unknown.0", usi => 100 ), '';
is $p->eval_var( "us.parent.id", usi => 100 ), 99;
is $p->eval_var( "us.parent.user_service_id", usi => 100 ), 99;
is $p->eval_var( "us.parent.settings", usi => 100 ), '{"quota":"10000"}';
is $p->eval_var( "us.parent.settings.quota", usi => 100 ), 10000;

is $p->eval_var( "us.child_by_category('web').id", usi => 99 ), 101;
is $p->eval_var( "child('web').id", usi => 99 ), 101;
is $p->eval_var( "child('web').server.settings.host_name", usi => 99 ), 'host1.domain.ru';

subtest 'Test gen_store_pass()' => sub {
    my $pass = $p->eval_var( "us.parent.gen_store_pass(5)", usi => 100 );
    is length( $pass ), 5;

    my $us = get_service('us', _id => 99 );
    is_deeply( $us->settings, {
        'quota' => '10000',
        'password' => $pass,
    });
};

subtest 'Test parse()' => sub {
    my $string = '--id={{ id }} --quota={{ us.parent.settings.quota }}';

    my $ret = $p->parse( $string, usi => 101 );
    is $ret, '--id=101 --quota=10000';

};

subtest 'Test function parse' => sub {
    my $ret = $p->parse( "{{ passgen }}");
    is length( $ret), 10;

    $ret = $p->parse( "{{ passgen() }}");
    is length( $ret), 10;

    $ret = $p->parse( "{{ passgen(3) }}");
    is length( $ret), 3;
};


done_testing();
