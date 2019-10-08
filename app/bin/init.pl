#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw( read_file );
use Data::Dumper;

my $self = SHM->new( skip_check_auth => 1 );

my $tables_count = $self->do("SHOW TABLES");

unless ( $tables_count ) {
    print "Init database... ";
    import_sql_file( $self->dbh, "$ENV{SHM_ROOT_DIR}/sql/shm/shm_structure.sql" );
    import_sql_file( $self->dbh, "$ENV{SHM_ROOT_DIR}/sql/shm/shm_data.sql" );
    say "done";
}

exit 0;

sub import_sql_file {
    my $dbh = shift;
    my $file = shift;

    my $data = read_file( $file ) or die "Can't read file: $file";

    my @sql = sql_split( $data );

    for ( @sql ) {
        $dbh->do( $_ );
    }
}

sub sql_split {
    my $sql = shift;

    my @statements = ("");
    my @tokens     = grep { ord } split /([\\';])/, $sql;
    my $in_string  = 0;
    my $escape     = 0;

    while (@tokens) {
        my $token = shift @tokens;
        if ($in_string) {
            $statements[-1] .= $token;
            if ($token eq "\\") {
                $escape = 1;
                next;
            }
            $in_string = 0 if not $escape and $token eq "'";
            $escape = 0;

            next;
        }
        if ($token eq ';') {
            push @statements, "";
            next;
        }
        $statements[-1] .= $token;
        $in_string = 1 if $token eq "'";
    }
    return grep { /\S/ } @statements;
}

