use v5.14;
use Test::More;
use Data::Dumper;
use Core::System::ServiceManager qw( get_service );

$ENV{SHM_TEST} = 1;
$ENV{DEBUG} = 'ERROR';

my $report = get_service('report');

$report->add_error('my big error');
is_deeply scalar $report->errors, ['my big error'], 'Check for one recors';
is_deeply scalar $report->errors, [], 'Check for empty records';

$report->add_error('first error');
$report->add_error('second error');
$report->add_error('last error');
$report->add_error( { foo => 'bar' } );
$report->add_error('one','two','free');

is $report->is_success, 0, 'Check report status: fail';

is_deeply scalar $report->errors, [
    'first error',
    'second error',
    'last error',
    { foo => 'bar' },
    'one two free',
], 'Check multiple errors';

is $report->is_success, 1, 'Check report status: success';
is_deeply scalar $report->errors, [], 'Check for empty records after get multiple errors';

$report->status(409);
$report->headers({ 'X-Test-Header' => 'ok' });

my $headers = $report->headers;
is $headers->{status}, 409, 'Report headers include status from report';
is $headers->{'X-Test-Header'}, 'ok', 'Report headers preserve custom values';

my %headers = $report->headers;
is $headers{status}, 409, 'Report headers in list context include status';
is $headers{'X-Test-Header'}, 'ok', 'Report headers in list context preserve custom values';

done_testing();
