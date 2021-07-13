use v5.14;
use warnings;

use Test::More;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $t = get_service('template', _id => 1);

my $ret = $t->parse( usi => 99 );

is $ret, 'Здравствуйте Фирсов Даниил Андреевич

Вы зарегистрировали новую услугу: Тариф X-MAX (${QUOTA} мб)

Дата истечения услуги: 2017-01-31 23:59:50

Стоимость услуги: 300 руб.

Хостинг сайтов:
Хост: host1.domain.ru
Логин: w_101
Пароль: enos1aer

Желаем успехов.';

done_testing();
