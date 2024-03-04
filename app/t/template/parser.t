use v5.14;
use warnings;

use Test::More;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

subtest 'Check template 1' => sub {
    my $t = get_service('template', _id => 'web_tariff_create');

    my $ret = $t->parse( usi => 99 );

    is $ret, 'Здравствуйте Фирсов Даниил Андреевич

Вы зарегистрировали новую услугу: Тариф X-MAX (10000 мб)

Дата истечения услуги: 2017-01-31 23:59:50

Стоимость услуги: 300 руб.

Хостинг сайтов:
Хост: host1.domain.ru
Логин: w_101
Пароль: enos1aer

Желаем успехов.';
};

subtest 'Check toJson function' => sub {
    my $t = get_service('template');

    my $json = $t->parse(
        data => '{{ toJson(
            {
                a => 1,
                b => 2,
            }
        ) }}',
    );

    is( $json, '{"a":1,"b":2}' );
};

subtest 'Check EVAL_PERL' => sub {
    my $t = get_service('template');

    my $perl = $t->parse(
        data => '
            {{ PERL }}
                use v5.14;
                say "My login is: {{ user.login }}";
            {{ END -}}
        ',
    );

    is( $perl, 'My login is: danuk' );
};

subtest 'Check template trim' => sub {
    my $t = get_service('template');

    my $data = $t->parse(
        data => '
                Hello world

        ',
    );

    is( $data, 'Hello world' );
};

subtest 'Check forecast via template' => sub {
    my $t = get_service('template');

    is( $t->parse( data => '{{ user.id( 1 ).pays.forecast.total }}' ), 0 );
    is( $t->parse( data => '{{ user.id( 40092 ).pays.forecast.total }}' ), 1035.01 );
    is( $t->parse( data => '{{ user.pays.forecast.total }}' ), 1035.01 );
};

done_testing();
