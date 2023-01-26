use strict;
use warnings;

use Test::More;
use v5.14;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

my $user = SHM->new( user_id => 40092 );

my $logger = get_service('logger');

my $ret = $logger->make_message(
    tag => 0,
    time => 0,
    pid => 0,
    color => 0,
    stacktrace => 0,
    msg => [
        'test',
        'foo',
        {
            a => 1,
            b => 2,
            c => [ 0, 'z', d => { e => 1 } ],
        },
    ],
);

is $ret, sprintf "message: {{ %s }}", 'test foo {"a":1,"b":2,"c":[0,"z","d",{"e":1}]}';


done_testing();
