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

subtest 'Check template 3' => sub {
    my $t = get_service('template', _id => 'forecast');

    my $ret = $t->parse();

    is $ret, 'Уважаемый Фирсов Даниил Андреевич

Уведомляем Вас о сроках действия услуг:

- Услуга: Тариф X-MAX (10000 мб)
  Стоимость: 123.45 руб.
  Истекает: 2017-01-31 23:59:50
- Услуга: Продление домена в зоне .RU: umci.ru
  Стоимость: 890 руб.
  Истекает: 2017-07-29 12:39:46

Погашение задолженности: 21.56 руб.

Итого к оплате: 1035.01 руб.

Услуги, которые не будут оплачены до срока их истечения, будут приостановлены.

Подробную информацию по Вашим услугам Вы можете посмотреть в вашем личном кабинете: http://127.0.0.1:8081

Это письмо сформировано автоматически. Если оно попало к Вам по ошибке,
пожалуйста, сообщите об этом нам: mail@domain.ru';
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

done_testing();
