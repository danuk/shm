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

my @domains = get_service('domain')->list_domains_for_service( user_service_id => 100 );
is scalar @domains, 2, 'Load domains for user_service';

@recs = $domain->get_domain( user_service_id => 16 )->dns_records;
is $recs[0]->{domain}, 'danuk.ru';

is_deeply get_service('domain', _id => 6)->list_services_for_domain, [101,100,16],'Check list of services';

is ( $domain->check_domain('test.ru'), 1, 'Check domain name' );
is ( $domain->check_domain('test.r'), 0, 'Check wrong domain name' );
is ( $domain->to_punycode('привет.рф'), 'xn--b1agh1afp.xn--p1ai', 'Convert domain to punycode' );
is ( $domain->to_punycode('test.ru'), undef, 'No convert domain to punycode' );

done_testing();
