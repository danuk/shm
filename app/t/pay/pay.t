use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw( now );
use SHM ();

$ENV{SHM_TEST} = 1;

my $user = SHM->new( user_id => 40092 );

my $spool = get_service('spool');

subtest 'Check existed last payment' => sub {
    cmp_deeply ( scalar $user->pays->last->res, superhashof({
        id => ignore(),
        date => ignore(),
        user_id => 40092,
        pay_system_id => 'manual',
        money => 455,
    }));
};

subtest 'Make new payment and check last' => sub {
    my $payment = $user->payment(
        money => 14,
        pay_system_id => 'test',
        comment => {
            test => 1,
        },
        uniq_key => '123xxx',
    );

    cmp_deeply ( scalar $user->pays->last->res, superhashof({
        id => ignore(),
        date => ignore(),
        user_id => 40092,
        pay_system_id => $payment->{pay_system_id},
        money => $payment->{money},
        comment => $payment->{comment},
        uniq_key => $payment->{uniq_key},
    }));

    cmp_deeply( ($spool->list)[0], superhashof({
          user_id => 40092,
          status => 'NEW',
          event => {
              method => 'activate_services',
              kind => 'UserService',
              title => 'user payment'
          },
    }));

    $spool->process_all();

    my @spool = $spool->list;
    is( scalar @spool, 0 );
};

subtest 'Make new payment when us is locked' => sub {
    $spool->_delete();

    my $payment = $user->payment(
        money => 1,
        pay_system_id => 'test',
    );

    my $us = $user->us->id(99)->set('status', 'PROGRESS');

    cmp_deeply( ($spool->list)[0], superhashof({
          user_id => 40092,
          status => 'NEW',
          event => {
              method => 'activate_services',
              kind => 'UserService',
              title => 'user payment'
          },
    }));

    $spool->process_all();

    cmp_deeply( ($spool->list)[0], superhashof({
          user_id => 40092,
          status => 'FAIL',
          event => {
              method => 'activate_services',
              kind => 'UserService',
              title => 'user payment'
          },
    }));


    $spool->_delete();
};


done_testing();

