use v5.14;

use Test::More;
use Data::Dumper;

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use SHM;

my $report = get_service('report');

$report->add_error('my big error');
is_deeply scalar $report->errors, ['my big error'], 'Check for one recors';

is_deeply scalar $report->errors, [], 'Check for empty records';

$report->add_error('first error');
$report->add_error('second error');
$report->add_error('last error');
$report->add_error( { foo => 'bar' } );

is $report->is_success, 0, 'Check report status: fail';

is_deeply scalar $report->errors, [
    'first error',
    'second error',
    'last error',
    { foo => 'bar' },
], 'Check multiple errors';

is $report->is_success, 1, 'Check report status: success';
is_deeply scalar $report->errors, [], 'Check for empty records after get multiple errors';

done_testing();
