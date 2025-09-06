use v5.14;
use warnings;
use utf8;

use Test::More;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::Const;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $spool = get_service('spool');

no warnings 'once';
*Core::Spool::make_task = sub {
    my $self = shift;
    my %args = @_;
    return 'MOCK', \%args;
};

subtest 'Get server_id by event settings' => sub {
    my $task_id = $spool->add(
        event => {
            kind => 'user_service',
            name => 'update',
            server_gid => 1,
            info => 't/spool/make_task.t',
        },
        settings => {
            user_service_id => 16,
            server_id => 2,
        },
    );

    my %task = $spool->id( $task_id )->get;
    is ( $task{id}, $task_id );

    my ( $info ) = $spool->process_one( \%task );

    is( $info->get_status, 'MOCK' );
    is( $info->get_settings->{server_id} =~ /^1|2$/, 1 );
};

subtest 'Get server_id by server_gid' => sub {
    my $task_id = $spool->add(
        event => {
            kind => 'user_service',
            name => 'update',
            server_gid => 5,
            info => 't/spool/make_task.t',
        },
        settings => {
            user_service_id => 16,
        },
    );

    my %task = $spool->id( $task_id )->get;
    is ( $task{id}, $task_id );

    my ( $info ) = $spool->process_one( \%task );

    is( $info->get_status, 'MOCK' );
    is( $info->get_settings->{server_id}, 25 );
};

done_testing();
