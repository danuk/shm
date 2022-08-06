use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw( now );
use SHM ();

$ENV{SHM_TEST} = 1;
SHM->new( user_id => 40092 );

my $pay = get_service('pay');

subtest 'Check forecast' => sub {
    my $ret = $pay->forecast();

    cmp_deeply( $ret, {
        items => bag(
            {
                name => 'Регистрация домена в зоне .RU: umci.ru',
                usi => 2949,
                expire => '2017-07-29 12:39:46',
                cost => 590,
                total => 590,
                discount => 0,
                qnt => 1,
                months => 12,
            },
            {
                name => 'Тариф X-MAX (10000 мб)',
                usi => 99,
                expire => '2017-01-31 23:59:50',
                cost => 123.45,
                total => 123.45,
                discount => 0,
                qnt => 1,
                months => 1,
            }
        ),
        dept => 21.56,
        total => 735.01,
    });
};

subtest 'Check forecast with next wd' => sub {
    get_service('withdraw')->add(
        user_id => 40092,
        service_id => 110,
        user_service_id => 99,
        cost => 100,
        months => 1,
    );

    my $ret = $pay->forecast();

    cmp_deeply( $ret, {
        items => bag(
            {
                name => 'Регистрация домена в зоне .RU: umci.ru',
                usi => 2949,
                expire => '2017-07-29 12:39:46',
                cost => 590,
                total => 590,
                discount => 0,
                qnt => 1,
                months => 12,
            },
            {
                name => 'Тариф X-MAX (10000 мб)',
                usi => 99,
                expire => '2017-01-31 23:59:50',
                cost => 100.00,
                total => 100.00,
                discount => 0,
                qnt => 1,
                months => 1,
            }
        ),
        dept => 21.56,
        total => 711.56,
    });
};

subtest 'Check forecast with next already payed wd' => sub {
    my %wd_next = get_service('us', _id => 99 )->withdraw->next;
    my $wd_next_id = $wd_next{withdraw_id};

    get_service('withdraw', _id => $wd_next_id )->set( withdraw_date => now() );

    my $ret = $pay->forecast();

    cmp_deeply( $ret, {
        items => bag(
            {
                name => 'Регистрация домена в зоне .RU: umci.ru',
                usi => 2949,
                expire => '2017-07-29 12:39:46',
                cost => 590,
                total => 590,
                discount => 0,
                qnt => 1,
                months => 12,
            },
        ),
        dept => 21.56,
        total => 611.56,
    });
};

done_testing();
