use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::Billing;
use Core::System::ServiceManager qw( get_service );
use SHM;

$ENV{SHM_TEST} = 1;

SHM->new( user_id => 40092 );

my %wd;

subtest 'Check withdraw domain for one month' => sub {
    %wd = Core::Billing::calc_withdraw(
        'Honest',
        withdraw_date => '2019-01-01 00:00:00',
        service_id => 11,
        period => 12,
        cost => 1200,
        months => 1,
    );

    cmp_deeply ( \%wd, superhashof({
        withdraw_date   => '2019-01-01 00:00:00',
        end_date        => '2019-01-31 23:59:59',
        service_id      => 11,
        months          => 1,
        cost            => 1200,
        total           => 100,
        qnt             => 1,
        discount        => 0,
    }));
};

subtest 'Check withdraw domain for one year' => sub {
    %wd = Core::Billing::calc_withdraw(
        'Honest',
        withdraw_date => '2019-01-01 00:00:00',
        service_id => 11,
        cost => 600,
        months => 12,
    );

    cmp_deeply ( \%wd, superhashof({
        withdraw_date   => '2019-01-01 00:00:00',
        end_date        => '2019-12-31 23:59:59',
        service_id      => 11,
        months          => 12,
        cost            => 600,
        total           => 600,
        qnt             => 1,
        discount        => 0,
    }));
};

subtest 'Check withdraw service for month' => sub {
    %wd = Core::Billing::calc_withdraw(
        'Honest',
        withdraw_date => '2019-01-01 00:00:00',
        service_id => 1,
        period => 1,
        cost => 310,
        months => 1,
    );

    cmp_deeply ( \%wd, superhashof({
        withdraw_date   => '2019-01-01 00:00:00',
        end_date        => '2019-01-31 23:59:59',
        service_id      => 1,
        months          => 1,
        cost            => 310,
        total           => 310,
        qnt             => 1,
        discount        => 0,
    }));
};

subtest 'Check withdraw service for one day' => sub {
    %wd = Core::Billing::calc_withdraw(
        'Honest',
        withdraw_date => '2019-01-01 00:00:00',
        service_id => 1,
        cost => 310,
        months => 0.01,
    );

    cmp_deeply ( \%wd, superhashof({
        withdraw_date   => '2019-01-01 00:00:00',
        end_date        => '2019-01-01 23:59:59',
        service_id      => 1,
        months          => 0.01,
        cost            => 310,
        total           => 10,
        qnt             => 1,
        discount        => 0,
    }));
};

subtest 'Check withdraw service for two days' => sub {
    %wd = Core::Billing::calc_withdraw(
        'Honest',
        withdraw_date => '2019-01-01 00:00:00',
        service_id => 1,
        cost => 310,
        months => 0.02,
    );

    cmp_deeply ( \%wd, superhashof({
        withdraw_date   => '2019-01-01 00:00:00',
        end_date        => '2019-01-02 23:59:59',
        service_id      => 1,
        months          => 0.02,
        cost            => 310,
        total           => 20,
        qnt             => 1,
        discount        => 0,
    }));
};

subtest 'Check withdraw service for 13 days' => sub {
    %wd = Core::Billing::calc_withdraw(
        'Honest',
        withdraw_date => '2019-01-01 00:00:00',
        service_id => 1,
        cost => 310,
        months => 0.13,
    );

    cmp_deeply ( \%wd, superhashof({
        withdraw_date   => '2019-01-01 00:00:00',
        end_date        => '2019-01-13 23:59:59',
        service_id      => 1,
        months          => 0.13,
        cost            => 310,
        total           => 130,
        qnt             => 1,
        discount        => 0,
    }));
};

subtest 'Check withdraw service with discount' => sub {
    %wd = Core::Billing::calc_withdraw(
        'Honest',
        withdraw_date => '2019-01-01 00:00:00',
        service_id => 1,
        cost => 600,
        months => 1,
        discount => 20,
    );

    cmp_deeply ( \%wd, superhashof({
        withdraw_date   => '2019-01-01 00:00:00',
        end_date        => '2019-01-31 23:59:59',
        service_id      => 1,
        months          => 1,
        cost            => 600,
        total           => 480,
        qnt             => 1,
        discount        => 20,
    }));
};

done_testing();

