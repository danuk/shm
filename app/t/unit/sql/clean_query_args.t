use v5.14;
use utf8;

use Test::More;
use Test::Deep;
use Core::Sql::Data qw/clean_query_args/;

# Minimal mock object: only fields with `default`, no key/required/auto_fill/now
package MockModel;
sub new { bless {}, shift }
sub structure {
    return {
        login2  => { type => 'text',   default => undef },
        score   => { type => 'number', default => 0     },
        meta    => { type => 'json',   default => {}    },
        comment => { type => 'text',   default => ''    },
        name    => { type => 'text'                     }, # no default
    };
}
sub get_table_key        { return 'id' }
sub table_allow_insert_key { return 0 }

package main;

my $mock = MockModel->new;

subtest 'default => undef: empty string becomes undef' => sub {
    my %args = ( login2 => '' );
    clean_query_args( $mock, \%args );
    is( $args{login2}, undef, 'empty string converted to undef' );
};

subtest 'default => 0: empty string becomes 0' => sub {
    my %args = ( score => '' );
    clean_query_args( $mock, \%args );
    is( $args{score}, 0, 'empty string converted to 0' );
};

subtest 'default => {}: empty string becomes {}' => sub {
    my %args = ( meta => '' );
    clean_query_args( $mock, \%args );
    cmp_deeply( $args{meta}, {}, 'empty string converted to {}' );
};

subtest 'default => "": empty string stays empty string' => sub {
    my %args = ( comment => '' );
    clean_query_args( $mock, \%args );
    is( $args{comment}, '', 'empty string stays empty string when default is ""' );
};

subtest 'no default: empty string left unchanged' => sub {
    my %args = ( name => '' );
    clean_query_args( $mock, \%args );
    is( $args{name}, '', 'empty string not touched when no default' );
};

subtest 'non-empty value: not converted' => sub {
    my %args = ( login2 => 'somevalue', score => 42 );
    clean_query_args( $mock, \%args );
    is( $args{login2}, 'somevalue', 'non-empty login2 unchanged' );
    is( $args{score},  42,          'non-zero score unchanged' );
};

subtest 'undef value: gets default via //= (existing behaviour)' => sub {
    my %args = ( login2 => undef, score => undef );
    clean_query_args( $mock, \%args );
    is( $args{login2}, undef, 'undef login2 stays undef (default is undef)' );
    is( $args{score},  0,     'undef score gets default 0 via //=' );
};

done_testing;
