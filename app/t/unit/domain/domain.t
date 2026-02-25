use strict;
use warnings;

use Test::More;
use Test::Deep;

use Data::Dumper;
use v5.14;
use utf8;

$ENV{SHM_TEST} = 1;

use SHM;
use Core::System::ServiceManager qw( get_service );

SHM->new( user_id => 40092 );

my $domain = get_service('domain', _id => 308 );
is $domain->get->{domain}, 'umci.ru';

my @recs = $domain->get_domain( name => 'umci.ru' )->dns->records;
is $recs[0]->{addr}, '37.46.134.76';

my @domains = get_service('domain')->list_services( user_service_id => 100 );
is scalar @domains, 2, 'Load domains for user_service';

my %d = get_service('domain')->get_domain( user_service_id => 16 )->get;
is_deeply( \%d,
{
	'user_service_id' => 16,
	'created' => '2017-01-01 00:00:00',
	'subdomain_for' => undef,
	'domain' => 'danuk.ru',
	'zone_id' => 0,
	'user_id' => 40092,
	'punycode' => undef,
	'domain_id' => 6
}
,'Check get_domain by user_service_id');

my @domain_services = get_service('domain', _id => 6)->list_services;
cmp_deeply( \@domain_services,
bag(
	{
		'id' => ignore(),
		'user_service_id' => 16,
		'domain_id' => 6,
		'created' => '2017-09-23 00:00:01'
	},
	{
		'id' => ignore(),
		'user_service_id' => 100,
		'domain_id' => 6,
		'created' => '2017-09-23 23:54:23'
	},
	{
		'id' => ignore(),
		'domain_id' => 6,
		'user_service_id' => 101,
		'created' => '2017-09-23 23:54:04'
	},
	{
		'id' => ignore(),
		'user_service_id' => 2950,
		'domain_id' => 6,
		'created' => '2017-11-05 17:40:30',
	},
	{
		'id' => ignore(),
		'created' => '2017-11-05 17:40:33',
		'domain_id' => 6,
		'user_service_id' => 2951
	},
), 'Check list of services');

is ( $domain->check_domain('test.ru'), 1, 'Check domain name' );
is ( $domain->check_domain('test.r'), 0, 'Check wrong domain name' );
is ( $domain->to_punycode('привет.рф'), 'xn--b1agh1afp.xn--p1ai', 'Convert domain to punycode' );
is ( $domain->to_punycode('test.ru'), undef, 'No convert domain to punycode' );

done_testing();
