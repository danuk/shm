use strict;
use warnings;
use Test::More;
use Core::Utils qw(hash_merge);

my $h1 = { a => 1, b => 2 };
my $h2 = { b => 3, c => 4 };
my $merged = hash_merge({%$h1}, $h2);
is_deeply($merged, { a => 1, b => 3, c => 4 }, 'simple merge');

my $h3 = { x => { y => 1, z => 2 }, w => 5 };
my $h4 = { x => { z => 3, k => 4 }, w => 6 };
my $merged2 = hash_merge({%$h3}, $h4);
is_deeply($merged2, { x => { y => 1, z => 3, k => 4 }, w => 6 }, 'nested hash merge');

my $h5 = { a => 1, b => 2 };
my $h6 = { b => 3, c => 4 };
my $h7 = { c => 5, d => 6 };
my $merged3 = hash_merge({%$h5}, $h6, $h7);
is_deeply($merged3, { a => 1, b => 3, c => 5, d => 6 }, 'merge three hashes');

my $merged4 = hash_merge({}, undef);
is_deeply($merged4, {}, 'merge with undef returns empty hash');

my $h8 = { a => { x => 1 }, b => 2 };
my $h9 = { a => { y => 5 }, c => 3 };
my $merged5 = hash_merge({%$h8}, $h9);
is_deeply($merged5, { a => { x => 1, y => 5 }, b => 2, c => 3 }, 'merge with different structure (hash vs scalar)');

my $h10 = { b => { x => 1 } };
my $h11 = { a => { y => 5 }, b => 7 };
my $merged6 = hash_merge({%$h10}, $h11);
is_deeply($merged6, { a => { y => 5 }, b => 7 }, 'merge with different structure (array vs hash, hash vs scalar)');

my $merged7 = hash_merge('', $h11);
is_deeply($merged7, $h11, 'merge left empty');

my $merged8 = hash_merge($h10, '');
is_deeply($merged8, $h10, 'merge right empty');

my $merged9 = hash_merge('', '');
is_deeply($merged9, {}, 'merge empty');

done_testing;
