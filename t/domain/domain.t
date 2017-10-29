use strict;
use warnings;

use Test::More;

use Data::Dumper;
use v5.14;
use utf8;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $domain = get_service('domain', _id => 308 );
is $domain->get->{domain}, 'umci.ru';

my @recs = $domain->get_domain( name => 'umci.ru' )->dns_records;
is $recs[0]->{addr}, '37.46.134.76';

my @domains = get_service('domain')->list_services( user_service_id => 100 );
is scalar @domains, 2, 'Load domains for user_service';

@recs = $domain->get_domain( user_service_id => 16 )->dns_records;
is $recs[0]->{domain}, 'danuk.ru';

my @domain_services = get_service('domain', _id => 6)->list_services;
is_deeply( \@domain_services,
[
    {
        'domain_id' => 6,
        'id' => 27,
        'created' => '2017-10-29 15:45:04',
        'user_service_id' => 16
    },
    {
        'domain_id' => 6,
        'id' => 15,
        'user_service_id' => 100,
        'created' => '2017-09-23 23:54:23'
    },
    {
        'user_service_id' => 101,
        'created' => '2017-09-23 23:54:04',
        'domain_id' => 6,
        'id' => 1
    },
], 'Check list of services');

is ( $domain->check_domain('test.ru'), 1, 'Check domain name' );
is ( $domain->check_domain('test.r'), 0, 'Check wrong domain name' );
is ( $domain->to_punycode('привет.рф'), 'xn--b1agh1afp.xn--p1ai', 'Convert domain to punycode' );
is ( $domain->to_punycode('test.ru'), undef, 'No convert domain to punycode' );

done_testing();
