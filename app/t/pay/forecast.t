use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw( now );
use SHM ();
use utf8;

$ENV{SHM_TEST} = 1;
my $user = SHM->new( user_id => 40092 );

subtest 'Check curent us' => sub {
    my $us = get_service('us', _id => 2949 );
    is ( $us->name, 'Регистрация домена в зоне .RU: umci.ru', 'Check current us name' );
    is ( $us->withdraw->get_cost, 590, 'Check current us cost' );
    is ( $us->withdraw->get_total + $us->withdraw->get_bonus, 590, 'Check current us total' );
};

my $pay = get_service('pay');

subtest 'Check forecast' => sub {
    my $ret = $pay->forecast();

    cmp_deeply( $ret, {
        items => bag(
            {
                name => 'Регистрация домена в зоне .RU: umci.ru',
                service_id => 11,
                usi => 2949,
                user_service_id => 2949,
                expire => '2017-07-29 12:39:46',
                cost => 590,
                total => 578.2,
                discount => 0,
                qnt => 1,
                months => 12,
                status => 'ACTIVE',
                next => {
                    total => 890,
                    name => 'Продление домена в зоне .RU: umci.ru',
                    discount => 0,
                    months => 12,
                    service_id => 12,
                    cost => 890,
                    qnt => 1
                },
            },
            {
                name => 'Тариф X-MAX (10000 мб)',
                service_id => 110,
                usi => 99,
                user_service_id => 99,
                expire => '2017-01-31 23:59:50',
                cost => 123.45,
                total => 123.45,
                discount => 0,
                qnt => 1,
                months => 1,
                status => 'ACTIVE',
                next => {
                    total => 123.45,
                    discount => 0,
                    name => 'Тариф X-MAX (10000 мб)',
                    months => 1,
                    cost => 123.45,
                    qnt => 1,
                    service_id => 110
                },
            },
        ),
        balance => -21.56,
        bonuses => 0,
        dept => 21.56,
        total => 1035.01,
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
                service_id => 11,
                usi => 2949,
                user_service_id => 2949,
                expire => '2017-07-29 12:39:46',
                cost => 590,
                total => 578.2,
                discount => 0,
                qnt => 1,
                months => 12,
                status => 'ACTIVE',
                next => {
                    name => 'Продление домена в зоне .RU: umci.ru',
                    total => 890,
                    service_id => 12,
                    months => 12,
                    discount => 0,
                    cost => '890',
                    qnt => 1
                },
            },
            {
                name => 'Тариф X-MAX (10000 мб)',
                service_id => 110,
                usi => 99,
                user_service_id => 99,
                expire => '2017-01-31 23:59:50',
                cost => 123.45,
                total => 123.45,
                discount => 0,
                qnt => 1,
                months => 1,
                status => 'ACTIVE',
                next => {
                    name => 'Тариф X-MAX (10000 мб)',
                    service_id => 110,
                    total => 100,
                    months => 1,
                    discount => 0,
                    cost => '100',
                    qnt => 1
                },
            }
        ),
        balance => -21.56,
        bonuses => 0,
        dept => 21.56,
        total => 1011.56,
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
                service_id => 11,
                name => 'Регистрация домена в зоне .RU: umci.ru',
                usi => 2949,
                user_service_id => 2949,
                expire => '2017-07-29 12:39:46',
                cost => 590,
                total => 578.2,
                discount => 0,
                qnt => 1,
                months => 12,
                status => 'ACTIVE',
                next => {
                    service_id => 12,
                    total => 890,
                    discount => 0,
                    name => 'Продление домена в зоне .RU: umci.ru',
                    cost => 890,
                    qnt => 1,
                    months => 12,
                },
            },
        ),
        balance => -21.56,
        bonuses => 0,
        dept => 21.56,
        total => 911.56,
    });


    $user->set_balance( balance => 321.56 );
    $ret = $pay->forecast();

    cmp_deeply( $ret, {
        items => bag(
            {
                service_id => 11,
                name => 'Регистрация домена в зоне .RU: umci.ru',
                usi => 2949,
                user_service_id => 2949,
                expire => '2017-07-29 12:39:46',
                cost => 590,
                total => 578.2,
                discount => 0,
                qnt => 1,
                months => 12,
                status => 'ACTIVE',
                next => {
                    service_id => 12,
                    total => 890,
                    discount => 0,
                    name => 'Продление домена в зоне .RU: umci.ru',
                    cost => '890',
                    qnt => 1,
                    months => 12,
                },
            },
        ),
        balance => 300,
        bonuses => 0,
        total => 590,
    });
};

done_testing();
