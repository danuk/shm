use strict;
use warnings;
use Test::More;
use Core::Utils qw(is_ip_allowed);

# Test IPv4 addresses
subtest 'IPv4 address validation' => sub {
    # Test single IP (no CIDR mask)
    ok(is_ip_allowed('192.168.1.1', ['192.168.1.1']), 'Exact IPv4 match');
    ok(is_ip_allowed('192.168.1.1', ['192.168.1.1/32']), 'Exact IPv4 match with /32');

    # Test subnet matching
    ok(is_ip_allowed('192.168.1.100', ['192.168.1.0/24']), 'IPv4 in /24 subnet');
    ok(is_ip_allowed('10.0.0.50', ['10.0.0.0/16']), 'IPv4 in /16 subnet');
    ok(is_ip_allowed('172.16.5.10', ['172.16.0.0/12']), 'IPv4 in /12 subnet');

    # Test edge cases for subnets
    ok(is_ip_allowed('192.168.1.0', ['192.168.1.0/24']), 'Network address itself');
    ok(is_ip_allowed('192.168.1.255', ['192.168.1.0/24']), 'Broadcast address');

    # Test /0 (any IP)
    ok(is_ip_allowed('1.2.3.4', ['0.0.0.0/0']), 'Any IPv4 with 0.0.0.0/0');

    # Test non-matching cases
    ok(!is_ip_allowed('192.168.2.1', ['192.168.1.0/24']), 'IPv4 not in subnet');
    ok(!is_ip_allowed('10.1.0.1', ['192.168.0.0/16']), 'Completely different network');

    # Test multiple networks
    my $networks = ['192.168.1.0/24', '10.0.0.0/8', '172.16.0.0/16'];
    ok(is_ip_allowed('192.168.1.50', $networks), 'Match first network in list');
    ok(is_ip_allowed('10.5.10.15', $networks), 'Match second network in list');
    ok(is_ip_allowed('172.16.100.200', $networks), 'Match third network in list');
    ok(!is_ip_allowed('203.0.113.1', $networks), 'No match in any network');
};

subtest 'IPv6 address validation' => sub {
    # Test exact IPv6 match
    ok(is_ip_allowed('2001:db8::1', ['2001:db8::1']), 'Exact IPv6 match');
    ok(is_ip_allowed('2001:db8::1', ['2001:db8::1/128']), 'Exact IPv6 match with /128');

    # Test IPv6 subnets
    ok(is_ip_allowed('2001:db8::1234', ['2001:db8::/32']), 'IPv6 in /32 subnet');
    ok(is_ip_allowed('2001:db8:1:2:3:4:5:6', ['2001:db8::/32']), 'IPv6 in /32 subnet (different address)');
    ok(is_ip_allowed('fe80::1', ['fe80::/10']), 'Link-local IPv6 address');

    # Test /0 (any IPv6)
    ok(is_ip_allowed('2001:db8::1', ['::/0']), 'Any IPv6 with ::/0');

    # Test non-matching cases
    ok(!is_ip_allowed('2001:db9::1', ['2001:db8::/32']), 'IPv6 not in subnet');
    ok(!is_ip_allowed('fe80::1', ['2001:db8::/32']), 'Different IPv6 network');

    # Test multiple IPv6 networks
    my $networks = ['2001:db8::/32', 'fe80::/10', '::1/128'];
    ok(is_ip_allowed('2001:db8::5678', $networks), 'Match first IPv6 network');
    ok(is_ip_allowed('fe80::abcd', $networks), 'Match second IPv6 network');
    ok(is_ip_allowed('::1', $networks), 'Match localhost IPv6');
    ok(!is_ip_allowed('2001:db9::1', $networks), 'No match in any IPv6 network');
};

subtest 'Mixed IPv4/IPv6 networks' => sub {
    my $mixed_networks = [
        '192.168.1.0/24',
        '10.0.0.0/8',
        '2001:db8::/32',
        'fe80::/10'
    ];

    # Test IPv4 matching in mixed list
    ok(is_ip_allowed('192.168.1.100', $mixed_networks), 'IPv4 match in mixed list');
    ok(is_ip_allowed('10.5.5.5', $mixed_networks), 'IPv4 match in mixed list');

    # Test IPv6 matching in mixed list
    ok(is_ip_allowed('2001:db8::cafe', $mixed_networks), 'IPv6 match in mixed list');
    ok(is_ip_allowed('fe80::1234', $mixed_networks), 'IPv6 match in mixed list');

    # Test non-matching in mixed list
    ok(!is_ip_allowed('203.0.113.1', $mixed_networks), 'IPv4 no match in mixed list');
    ok(!is_ip_allowed('2001:db9::1', $mixed_networks), 'IPv6 no match in mixed list');
};

subtest 'Edge cases and error conditions' => sub {
    # Test with undefined/empty IP
    ok(!is_ip_allowed(undef, ['192.168.1.0/24']), 'Undefined IP returns false');
    ok(!is_ip_allowed('', ['192.168.1.0/24']), 'Empty IP returns false');

    # Test with empty networks list
    ok(!is_ip_allowed('192.168.1.1', []), 'Empty networks list returns false');

    # Test with invalid IP addresses
    ok(!is_ip_allowed('999.999.999.999', ['192.168.1.0/24']), 'Invalid IPv4 address');
    ok(!is_ip_allowed('not.an.ip.address', ['192.168.1.0/24']), 'Non-IP string');

    # Test networks with invalid entries (should be skipped)
    my $mixed_valid_invalid = [
        'not-a-network',
        '192.168.1.0/24',  # valid
        'invalid-cidr',
        '10.0.0.0/8'       # valid
    ];
    ok(is_ip_allowed('192.168.1.50', $mixed_valid_invalid), 'Valid network found despite invalid entries');
    ok(is_ip_allowed('10.5.5.5', $mixed_valid_invalid), 'Second valid network found');
    ok(!is_ip_allowed('172.16.1.1', $mixed_valid_invalid), 'No match in networks with invalid entries');
};

subtest 'Specific subnet mask tests' => sub {
    # Test various IPv4 subnet sizes
    ok(is_ip_allowed('192.168.1.1', ['192.168.1.0/30']), '/30 subnet (4 addresses)');
    ok(!is_ip_allowed('192.168.1.5', ['192.168.1.0/30']), 'Outside /30 subnet');

    ok(is_ip_allowed('10.0.0.1', ['10.0.0.0/31']), '/31 subnet (2 addresses)');
    ok(!is_ip_allowed('10.0.0.2', ['10.0.0.0/31']), 'Outside /31 subnet');

    # Test IPv6 various prefix lengths
    ok(is_ip_allowed('2001:db8::1', ['2001:db8::/48']), 'IPv6 /48 subnet');
    ok(is_ip_allowed('2001:db8:0:1::1', ['2001:db8::/48']), 'IPv6 /48 subnet with third octet');
    ok(!is_ip_allowed('2001:db9::1', ['2001:db8::/48']), 'Outside IPv6 /48 subnet');

    ok(is_ip_allowed('2001:db8::1', ['2001:db8::/64']), 'IPv6 /64 subnet');
    ok(!is_ip_allowed('2001:db8:1::1', ['2001:db8::/64']), 'Outside IPv6 /64 subnet');
};

subtest 'Special IPv4 ranges' => sub {
    # Test loopback
    ok(is_ip_allowed('127.0.0.1', ['127.0.0.0/8']), 'Loopback network');
    ok(is_ip_allowed('127.255.255.255', ['127.0.0.0/8']), 'Loopback network end');

    # Test private networks (RFC 1918)
    ok(is_ip_allowed('10.0.0.1', ['10.0.0.0/8']), 'Private Class A');
    ok(is_ip_allowed('172.16.0.1', ['172.16.0.0/12']), 'Private Class B');
    ok(is_ip_allowed('172.31.255.254', ['172.16.0.0/12']), 'Private Class B end');
    ok(is_ip_allowed('192.168.0.1', ['192.168.0.0/16']), 'Private Class C');

    # Test link-local (RFC 3927)
    ok(is_ip_allowed('169.254.1.1', ['169.254.0.0/16']), 'Link-local IPv4');
};

subtest 'Special IPv6 ranges' => sub {
    # Test loopback
    ok(is_ip_allowed('::1', ['::1/128']), 'IPv6 loopback exact');

    # Test unique local addresses (fc00::/7)
    ok(is_ip_allowed('fc00::1', ['fc00::/7']), 'Unique local address fc00');
    ok(is_ip_allowed('fd00::1', ['fc00::/7']), 'Unique local address fd00');

    # Test link-local (fe80::/10)
    ok(is_ip_allowed('fe80::1', ['fe80::/10']), 'Link-local IPv6');
    ok(is_ip_allowed('febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff', ['fe80::/10']), 'Link-local IPv6 end range');

    # Test multicast (ff00::/8)
    ok(is_ip_allowed('ff02::1', ['ff00::/8']), 'IPv6 multicast');
};

done_testing;
