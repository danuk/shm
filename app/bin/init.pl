#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw( read_file );
use Core::Sql::Data;
use version;

my $sql = Core::Sql::Data->new;

my $version;
my $version_prefix;
if ( -f "$ENV{SHM_ROOT_DIR}/version" ) {
    $version = read_file( "$ENV{SHM_ROOT_DIR}/version" );
    chomp $version;
    say "SHM version: $version";
    if ( $version =~/(-.+)$/ ) {
        $version_prefix = $1;
        $version =~s/-.+$//;
    }
}

my $config = get_service('config');
my $dbh = db_connect( %{ $config->file->{config}{database} } ) or die "Can't connect to DN";
$config->local('dbh', $dbh );

my $tables_count = $sql->do("SHOW TABLES");

if ( $ENV{TRUNCATE_DB_ON_START} || $tables_count == 0 ) {
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
    $config->id( '_shm' )->set( value => { version => $version . $version_prefix } ) if $version;
    say "done";
} elsif ( $version ) {
    # Start migrations
    chdir "$ENV{SHM_ROOT_DIR}/bin/migrations";

    my $config = $config->id( '_shm' );
    my $cur_version = $config->get_data->{version};
    say "Current version: $cur_version";

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
        if ( version->parse( $nv ) > version->parse( '0.2.17' ) ) {
            import_sql_file( $dbh, "$nv.sql" );
        } else {
            eval `cat $nv`;
        }
        $config->set( value => { version => $nv . $version_prefix } );
        $dbh->commit();
        say "done"
    }

    $config->set( value => { version => $version . $version_prefix } );
}

$dbh->commit();
$dbh->disconnect();

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

