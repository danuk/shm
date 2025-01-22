use v5.14;

use Test::More;
use Test::Deep;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw( now );
use SHM ();

$ENV{SHM_TEST} = 1;

my $user = SHM->new( user_id => 40092 );

subtest 'Check existed last payment' => sub {
    cmp_deeply ( $user->pays->last, superhashof({
        id => ignore(),
        date => ignore(),
        user_id => 40092,
        pay_system_id => 'manual',
        money => 455,
    }));
};

subtest 'Make new payment and check last' => sub {
    $user->payment(
        money => 14,
        pay_system_id => 'test',
        comment => {
            test => 1,
        },
        uniq_key => '123xxx',
    );

    cmp_deeply ( $user->pays->last, superhashof({
        id => ignore(),
        date => ignore(),
        user_id => 40092,
        pay_system_id => 'test',
        money => '14',
        comment => {
            test => 1
        },
        uniq_key => '123xxx',
    }));
};


done_testing();
