#!/usr/bin/perl
use v5.14;
use utf8;
use strict;
use warnings;

use Test::More;
use File::Find;

my $lib_dir  = '/app/lib';
my $workers  = 8;

my @pm_files;
find(
    sub {
        return unless /\.pm$/;
        push @pm_files, $File::Find::name;
    },
    $lib_dir,
);

@pm_files = sort @pm_files;

plan tests => scalar @pm_files;

# Split files into N buckets
my @buckets;
for my $i ( 0 .. $#pm_files ) {
    push @{ $buckets[ $i % $workers ] }, $pm_files[$i];
}

# Each worker writes results to a pipe
my @results;
my @handles;

for my $bucket ( @buckets ) {
    pipe( my $reader, my $writer ) or die "pipe: $!";
    my $pid = fork() // die "fork: $!";

    if ( $pid == 0 ) {
        # Child
        close $reader;
        for my $file ( @$bucket ) {
            my $output = `perl -c "$file" 2>&1`;
            my $ok = ( $? == 0 ) ? 1 : 0;
            $output //= '';
            $output =~ s/\n/\\n/g;
            print $writer "$ok\t$file\t$output\n";
        }
        close $writer;
        exit 0;
    }

    close $writer;
    push @handles, $reader;
}

# Collect results from all workers
my %result_map;
for my $fh ( @handles ) {
    while ( my $line = <$fh> ) {
        chomp $line;
        my ( $ok, $file, $output ) = split( /\t/, $line, 3 );
        $output =~ s/\\n/\n/g;
        $result_map{$file} = { ok => $ok, output => $output };
    }
    close $fh;
}

# Wait for all children
while ( wait() != -1 ) {}

# Output TAP in sorted order
for my $file ( @pm_files ) {
    my $r = $result_map{$file};
    ok( $r->{ok}, "Syntax OK: $file" );
    diag( $r->{output} ) unless $r->{ok};
}
