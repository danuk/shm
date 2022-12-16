use v5.14;
use warnings;
use utf8;

use Test::More;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::Const;
use Core::System::ServiceManager qw( get_service );

my $user = SHM->new( user_id => 40092 );

my $event = get_service('events');
my $spool = get_service('spool');

subtest 'Common payment' => sub {
    my @list = $spool->list;
    is( scalar @list, 0 );

    $user->payment( money => 12 );

    @list = $spool->list;
    is( scalar @list, 1 );

    $spool->_delete;
};

subtest 'Add payment event' => sub {
    $event->add(
        title => 'payment event',
        name => 'payment',
        server_gid => 1,
        settings => {
            category => '%',
        },
    );

    my @events = $event->get_events(
        name => 'payment',
        category => '%',
    );

    is( scalar @events, 1 );
};

subtest 'Payment with extra event' => sub {
    my @list = $spool->list;
    is( scalar @list, 0 );

    $user->payment( money => 123 );

    @list = $spool->list;
    is( scalar @list, 2 );
};

done_testing();

