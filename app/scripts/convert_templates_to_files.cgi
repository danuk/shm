#!/usr/bin/perl

use v5.14;
use utf8;
use SHM qw(:all);
use Core::Utils qw(
    write_file
    encode_json
);

my $dir = "/app/data/templates";
mkdir $dir;
chown 33, 33, $dir;
chdir $dir;

POSIX::setgid(33); # www-data
POSIX::setuid(33); # www-data

my @files;
opendir(DIR, $dir) or die $!;
for ( readdir(DIR) ) {
    if ( $_ =~s/\.tpl$// ) {
        push @files, $_;
    }
}
closedir DIR;

if ( @files ) {
    say "Error: directory templates is not empty";
    exit 1;
}

my $self = SHM->new( user_id => 1 );

my $res = $self->query_by_name( "SELECT * FROM templates", 'id' );
$self->convert_sql_structure_data( $res );

for ( values %{$res} ) {
    say "Save file: $_->{id}";
    write_template_to_file( $_->{id}, $_->{data}, $_->{settings} );
}

say;
say "done";

exit 0;

sub write_template_to_file {
    my $file = shift;
    my $data = shift;
    my $settings = shift;
    write_file( "$dir/$file.tpl", $data );

    if ( $settings ) {
        my $json = encode_json( $settings, pretty => 1 );
        write_file( "$dir/$file.tpls", $json );
    }
}

