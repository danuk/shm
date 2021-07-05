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
                 total => 590,
                 expired => '2017-07-29 12:39:46',
                 usi => 2949,
                 name => 'Регистрация домена в зоне .RU: umci.ru',
            },
            {
                name => 'Тариф X-MAX (10000 мб)',
                usi => 99,
                expired => '2017-01-31 23:59:50',
                total => 123.45,
            }
        ),
        total => 713.45,
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
                 total => 590,
                 expired => '2017-07-29 12:39:46',
                 usi => 2949,
                 name => 'Регистрация домена в зоне .RU: umci.ru',
            },
            {
                name => 'Тариф X-MAX (10000 мб)',
                usi => 99,
                expired => '2017-01-31 23:59:50',
                total => 100.00,
            }
        ),
        total => 690.00,
    });
};

subtest 'Check forecast with next already payed wd' => sub {
    my %wd_next = get_service('us', _id => 99 )->withdraws->next;
    my $wd_next_id = $wd_next{withdraw_id};

    get_service('withdraw', _id => $wd_next_id )->set( withdraw_date => now() );

    my $ret = $pay->forecast();

    cmp_deeply( $ret, {
        items => bag(
            {
                 total => 590,
                 expired => '2017-07-29 12:39:46',
                 usi => 2949,
                 name => 'Регистрация домена в зоне .RU: umci.ru',
            },
        ),
        total => 590.00,
    });
};

done_testing();
