#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    read_file
    switch_user
);
use Core::Sql::Data;
use version;
use JSON::PP;

my $sql = Core::Sql::Data->new;
my $migration_boundary_version = version->parse('0.2.17');

my $version;
my $version_prefix;
if ( -f "$ENV{SHM_ROOT_DIR}/version.json" ) {
    my $version_json_str = read_file( "$ENV{SHM_ROOT_DIR}/version.json" );
    my $version_data = decode_json( $version_json_str );
    $version = $ENV{SHM_VERSION_OVERRIDE} || $version_data->{version};
    $version_prefix = "-" . $version_data->{commitSha};
    $version =~s/-.+$//;
    say "SHM version: $version$version_prefix";
}

my $logger = get_service('logger');
my $config = get_service('config');
my $dbh = db_connect( %{ $config->file->{config}{database} } ) or die "Can't connect to DN";
$config->local('dbh', $dbh );
switch_user( 1 );

my $tables_count = $sql->do("SHOW TABLES");

if ( $ENV{DEV} || $tables_count == 0 ) {
    if ( $ENV{DEV} && $ENV{DEV_DB_CLEANUP} && $tables_count ) {
        print "Cleanup database for developer mode... ";
        import_sql_file( $dbh, "$ENV{SHM_ROOT_DIR}/sql/shm/shm_dev_cleanup.sql" );
        say "done";
    }

    print "Creating structure of database... ";
    import_sql_file( $dbh, "$ENV{SHM_ROOT_DIR}/sql/shm/shm_structure.sql" );
    say "done";

    if ( $ENV{DEV} ) {
        print "Loading data for developers... ";
        import_sql_file( $dbh, "$ENV{SHM_ROOT_DIR}/sql/shm/shm_dev_test_data.sql" );
    } else {
        print "Loading data... ";
        import_sql_file( $dbh, "$ENV{SHM_ROOT_DIR}/sql/shm/shm_data.sql" );
    }
    $config->id( '_shm' )->set_value( { version => $version . $version_prefix } ) if $version;
    say "done";
} elsif ( $version ) {
    # Start migrations
    chdir "$ENV{SHM_ROOT_DIR}/bin/migrations";

    my $config = $config->id( '_shm' );
    my $cur_version = $ENV{SHM_VERSION_OVERRIDE_DB} || $config->get_data->{version};
    say "Current version: $cur_version";

    # Check version format (should be like 1.2.3-abcd)
    unless ( $cur_version && $cur_version =~ /^\d+\.\d+\.\d+-.+$/ ) {
        say "Invalid version format '$cur_version', using current version '$version'";
        $cur_version = $version . $version_prefix;
        $config->set_value( { version => $cur_version } );
    }

    $cur_version =~s/-.+$//;

    my @migrations = `ls`;
    for ( @migrations ) {
        chomp;
        ~s/\.sql$//;
    }

    my @versions = sort { version->parse( $a ) <=> version->parse( $b ) } @migrations;

    for my $nv ( @versions ) {
        next if version->parse( $nv ) <= version->parse( $cur_version );
        next if version->parse( $nv ) > version->parse( $version );

        say "Applying migration for version: $nv ...";
        eval {
            if ( version->parse( $nv ) > $migration_boundary_version ) {
                import_sql_file( $dbh, "$nv.sql" );
            } else {
                run_legacy_migration( $nv );
            }
            1;
        } or do {
            my $error = $@ || "Unknown migration error";
            chomp $error;
            eval { $dbh->rollback(); };
            die "Migration for version '$nv' failed: $error\n";
        };

        $config->set_value( { version => $nv . $version_prefix } );
        $dbh->commit() or die "Commit failed after migration '$nv': " . ( $dbh->errstr // 'unknown error' ) . "\n";
        say "done"
    }

    $config->set_value( { version => $version . $version_prefix } );
}

# Load cloud and download paysystems and templates
get_service('Cloud::Jobs')->startup();

$dbh->commit();
$dbh->disconnect();

exit 0;

sub import_sql_file {
    my $dbh = shift;
    my $file = shift;

    my $data = read_file( $file ) or die "Can't read file: $file";

    my @sql = sql_split( $data );

    for my $statement ( @sql ) {
        my $res = $dbh->do( $statement );
        die "SQL execution failed in '$file': " . ( $dbh->errstr // 'unknown error' ) . "\nStatement: $statement\n"
            unless defined $res;
    }
}

sub run_legacy_migration {
    my $file = shift;

    my $legacy_code = read_file( $file )
        or die "Can't read legacy migration file: $file\n";

    my $ok = eval $legacy_code;
    die "Legacy migration '$file' failed: $@\n" if $@;

    return $ok;
}

sub sql_split {
    my $sql       = shift;
    my $delimiter = ';';
    my @statements;

    while ( length $sql ) {
        # Handle DELIMITER directive (case-insensitive, at start of current position)
        if ( $sql =~ /\A\s*DELIMITER[ \t]+(\S+)[^\n]*(?:\n|\z)/si ) {
            $delimiter = $1;
            $sql = substr( $sql, $+[0] );
            next;
        }

        my $pos = _sql_find_delimiter( $sql, $delimiter );
        if ( defined $pos ) {
            my $stmt = substr( $sql, 0, $pos );
            push @statements, $stmt if $stmt =~ /\S/;
            $sql = substr( $sql, $pos + length($delimiter) );
        }
        else {
            push @statements, $sql if $sql =~ /\S/;
            last;
        }
    }

    return @statements;
}

sub _sql_find_delimiter {
    my ( $sql, $delim ) = @_;
    my $len       = length $sql;
    my $dlen      = length $delim;
    my $in_string = 0;
    my $escape    = 0;
    my $i         = 0;

    while ( $i < $len ) {
        my $c = substr( $sql, $i, 1 );
        if ( $in_string ) {
            if    ( $escape )        { $escape = 0 }
            elsif ( $c eq '\\' )     { $escape = 1 }
            elsif ( $c eq "'" )      { $in_string = 0 }
            $i++;
        }
        else {
            if ( $c eq "'" ) {
                $in_string = 1;
                $i++;
            }
            elsif ( $dlen <= $len - $i && substr( $sql, $i, $dlen ) eq $delim ) {
                return $i;
            }
            else { $i++ }
        }
    }
    return undef;
}

sub do_sql {
    my $data = shift;

    my @sql = sql_split( $data );

    my $report = get_service('report');

    for ( @sql ) {
        say $_;
        $sql->do( $_ );
        unless ( $report->is_success ) {
            say $_ for ( $report->errors );
            exit 1;
        }
    }
}

