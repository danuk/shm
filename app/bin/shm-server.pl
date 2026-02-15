#!/usr/bin/perl
use v5.14;
use strict;
use warnings;
use FCGI;
use FCGI::ProcManager;
use File::Spec;
use Cwd qw(realpath);
use IO::Handle;
use CGI;
use POSIX ();
use Time::HiRes qw(time);
use Redis;
use Data::Dumper;

# Override exit() globally (for ALL packages) to throw an exception
# instead of killing the worker process
my $EXIT_EXCEPTION = "FCGI_EXIT\n";
my $IN_REQUEST = 0;

BEGIN {
    *CORE::GLOBAL::exit = sub (;$) {
        if ($IN_REQUEST) {
            # Temporarily disable $SIG{__DIE__} so Logger doesn't catch our exception
            local $SIG{__DIE__};
            die $EXIT_EXCEPTION;
        }
        CORE::exit($_[0] // 0);
    };
}

# Configuration
my $listen_addr = '0.0.0.0';
my $listen_port = 9082;
my $num_workers = 4;
my $timeout = 300;
my $uid = 'www-data';
my $gid = 'www-data';
my $restart_flag_key = 'shm:restart:workers';
my $restart_flag_ttl = 300;
my $redis_host = 'redis';
my $redis_port = 6379;

# Document roots and mappings
my %doc_roots = (
    '/shm/pay_systems'  => '/app/data/pay_systems',
    '/shm/v1'           => '/app/public_html/shm/v1.cgi',
    '/'                 => '/app/public_html',
);

my @skip_logging = (
    qr{^/shm/healthcheck\.cgi},
);

# Save original STDERR before FCGI takes it over
open(my $REAL_STDERR, '>&', \*STDERR) or die "Cannot dup STDERR: $!";
$REAL_STDERR->autoflush(1);

sub log_msg {
    my ($msg) = @_;
    my @t = localtime;
    my $ts = sprintf '%04d-%02d-%02d %02d:%02d:%02d',
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0];
    print $REAL_STDERR "[$ts] [$$] $msg\n";
}

# Create listening socket using FCGI::OpenSocket
my $socket = FCGI::OpenSocket(":$listen_port", 100)
    or die "Cannot open socket on port $listen_port: $!";

log_msg("Starting FastCGI server with $num_workers workers on $listen_addr:$listen_port");

# Setup process manager
my $pm = FCGI::ProcManager->new({
    n_processes => $num_workers,
    die_on_inactivity_timeout => 0,
    pm_title => 'shm-server',
});

# Change privileges (after socket creation)
if ($> == 0) {  # if running as root
    my $uid_num = getpwnam($uid) or die "Cannot get uid for $uid: $!";
    my $gid_num = getgrnam($gid) or die "Cannot get gid for $gid: $!";
    $) = $gid_num;  # set effective gid
    $> = $uid_num;  # set effective uid
    log_msg("Changed privileges to $uid:$gid ($uid_num:$gid_num)");
}

# Create FCGI request object BEFORE forking
# Use separate filehandle for FCGI stderr to avoid mixing with our logs
open(my $FCGI_ERR, '>', '/dev/null') or die "Cannot open /dev/null: $!";
my $request = FCGI::Request(\*STDIN, \*STDOUT, $FCGI_ERR, \%ENV, $socket);

# Start process manager - forks worker processes
$pm->pm_manage();

$0 = 'shm-worker';
log_msg("Worker started, entering request loop (PID: $$)");
my $worker_start_time = time;

# Save clean environment before any request processing
my %CLEAN_ENV = %ENV;
my $max_requests = 1000;
my $request_count = 0;

while ($request_count < $max_requests && $request->Accept() >= 0) {
    $request_count++;
    $pm->pm_pre_dispatch();
    $IN_REQUEST = 1;

    # Ensure output is sent immediately, not buffered
    $| = 1;
    STDOUT->autoflush(1);

    my $req_start;
    eval {
        # Merge: keep clean env as base, overlay with FCGI request env
        my %request_env = %ENV;
        %ENV = (%CLEAN_ENV, %request_env);

        my $request_uri = $ENV{REQUEST_URI} // $ENV{DOCUMENT_URI} // $ENV{SCRIPT_NAME} // '';
        my $restart_after_request = 0;

        if (restart_flag_is_newer($worker_start_time)) {
            $restart_after_request = 1;
        }

        # Check if we should skip logging
        my $skip_log = 0;
        foreach my $pattern (@skip_logging) {
            if ($request_uri =~ $pattern) {
                $skip_log = 1;
                last;
            }
        }

        # Find appropriate script and path_info
        my ($script_filename, $script_path_info) = determine_script($request_uri);

        if (-e $script_filename && -x $script_filename) {
            $req_start = time;

            # Execute CGI script
            execute_cgi($script_filename, $script_path_info);

            unless ($skip_log) {
                my $method = $ENV{REQUEST_METHOD} // 'UNKNOWN';
                my $ms = int((time - $req_start) * 1000);
                log_msg("$method $request_uri - script: $script_filename ${ms}ms");
            }
        } else {
            print "Status: 404 Not Found\r\n";
            print "Content-Type: text/plain\r\n\r\n";
            print "Not Found: $script_filename\n";
            unless ($skip_log) {
                log_msg("404 - file not found or not executable: $script_filename");
            }
        }

        if ($restart_after_request) {
            log_msg("Restart requested, worker exiting (PID: $$)");
            $IN_REQUEST = 0;
            $pm->pm_post_dispatch();
            CORE::exit(0);
        }
    };
    if ($@ && $@ ne $EXIT_EXCEPTION) {
        log_msg("FATAL request error: $@");
    }

    # Flush output to ensure response reaches nginx
    STDOUT->flush();

    # Restore clean environment
    %ENV = %CLEAN_ENV;

    $IN_REQUEST = 0;
    $pm->pm_post_dispatch();
}

log_msg("Worker shutting down after $request_count requests (PID: $$)");
CORE::exit(0);

sub determine_script {
    my ($request_uri) = @_;

    # Remove query string
    my $path = $request_uri;
    $path =~ s{\?.*}{};

    # Normalize: collapse multiple slashes into one
    $path =~ s{/+}{/}g;

    # Try longest match first (most specific)
    foreach my $prefix (sort { length($b) <=> length($a) } keys %doc_roots) {
        if ($path =~ m{^\Q$prefix\E(/.*)?$}) {
            my $rest = $1 // '';
            my $target = $doc_roots{$prefix};

            # If target is a file (v1.cgi), return it with path_info
            if ($target =~ /\.cgi$/) {
                return ($target, $rest);
            }

            # Otherwise treat as directory
            # Ensure rest starts with /
            $rest = "/$rest" if $rest && $rest !~ m{^/};

            # If rest is empty or just /, use index
            if (!$rest || $rest eq '/') {
                return ("$target/index.cgi", '') if -e "$target/index.cgi";
                return ($target, '') if -f $target;
            }

            return ($target . $rest, '');
        }
    }

    # Fallback - ensure path starts with /
    $path = "/$path" if $path !~ m{^/};
    return ('/app/public_html' . $path, '');
}

sub execute_cgi {
    my ($script, $path_info) = @_;

    # Set up CGI environment
    $ENV{SCRIPT_FILENAME} = $script;
    $ENV{SCRIPT_NAME} = $script;
    $ENV{PATH_INFO} = $path_info // '';
    $ENV{DOCUMENT_ROOT} = '/app/public_html';

    # Set Perl library path
    $ENV{PERL5LIB} = '/app/lib:/app/conf';

    # v1.cgi: execute via do (shares loaded services via get_service)
    if ($script =~ /v1\.cgi$/) {
        execute_do($script);
    } else {
        # All other scripts: execute in forked subprocess (safe isolation)
        execute_fork($script);
    }
}

# Execute script in current process (shares ServiceManager state)
sub execute_do {
    my ($script) = @_;

    # Reset global state from Core::Utils that persists between requests
    no warnings 'once';
    $Core::Utils::is_header = 0;
    %Core::Utils::in = ();

    # Reset CGI.pm global cache - without this, CGI->new returns stale params
    CGI::initialize_globals();

    use Core::System::ServiceManager qw( $SERVICE_MANAGER unregister_all );

    local $SIG{ALRM} = sub { die "TIMEOUT\n" };
    alarm($timeout);

    eval {
        do $script;
        die $@ if $@;
    };
    my $err = $@;

    alarm(0);

    if ($err) {
        if ($err eq $EXIT_EXCEPTION) {
            # Normal exit() from script - this is OK
        } elsif ($err eq "TIMEOUT\n") {
            log_msg("Script timeout after $timeout seconds: $script");
            print "Status: 504 Gateway Timeout\r\n";
            print "Content-Type: text/plain\r\n\r\n";
            print "Script timeout\n";
        } else {
            log_msg("Script error: $script - $err");
            print "Status: 500 Internal Server Error\r\n";
            print "Content-Type: text/plain\r\n\r\n";
            print "Internal Server Error\n";
        }
    }

    # Clean up request-specific services (users, sessions, etc.)
    # Keeps shared services: Core::Sql::Data, Core::Config, Core::System::Logger
    unregister_all();

    # Clean Config local data (user_id, authenticated_user_id, etc.)
    # but preserve the DB connection handle for reuse
    if (my $config = Core::System::ServiceManager::is_registered('config')) {
        my $dbh = $config->local('dbh');
        $config->{config}->{local} = {};
        $config->local('dbh', $dbh) if $dbh;
    }
}

# Execute script in forked subprocess (full isolation, exit() is safe)
sub execute_fork {
    my ($script) = @_;

    # Read request body before fork
    my $body = '';
    if ($ENV{CONTENT_LENGTH} && $ENV{CONTENT_LENGTH} > 0) {
        read(STDIN, $body, $ENV{CONTENT_LENGTH});
    }

    # Create pipe manually so child writes to pipe (not FCGI STDOUT)
    pipe(my $reader, my $writer) or do {
        log_msg("Pipe failed: $!");
        print "Status: 500 Internal Server Error\r\n";
        print "Content-Type: text/plain\r\n\r\n";
        print "Pipe failed\n";
        return;
    };

    my $pid = fork();

    if (!defined $pid) {
        log_msg("Fork failed: $!");
        close($reader);
        close($writer);
        print "Status: 500 Internal Server Error\r\n";
        print "Content-Type: text/plain\r\n\r\n";
        print "Fork failed\n";
        return;
    }

    if ($pid == 0) {
        # Child process - will be replaced by exec()
        close($reader);

        # Detach from FCGI - redirect STDOUT to the pipe
        untie *STDIN;
        untie *STDOUT;
        untie *STDERR;
        open(STDOUT, '>&', $writer) or warn "Cannot redirect STDOUT: $!";
        close($writer);
        STDOUT->autoflush(1);
        open(STDERR, '>&', $REAL_STDERR) or warn "Cannot redirect STDERR: $!";

        # Provide request body via STDIN using a real pipe (not scalar ref)
        # exec'd process can't read from Perl scalar references
        if ($body) {
            pipe(my $body_r, my $body_w) or warn "Cannot create body pipe: $!";
            print $body_w $body;
            close($body_w);
            open(STDIN, '<&', $body_r) or warn "Cannot redirect STDIN: $!";
            close($body_r);
        } else {
            open(STDIN, '<', '/dev/null') or warn "Cannot open /dev/null for STDIN: $!";
        }

        $SIG{ALRM} = sub { POSIX::_exit(124) };
        alarm($timeout);

        # Use exec instead of do - works for both Perl scripts and binaries
        exec($script) or do {
            print "Status: 500 Internal Server Error\r\n";
            print "Content-Type: text/plain\r\n\r\n";
            print "Cannot exec $script: $!\n";
            POSIX::_exit(1);
        };
    }

    # Parent: read child output from pipe and send to FastCGI client
    close($writer);
    my $output = '';
    while (<$reader>) {
        $output .= $_;
    }
    close($reader);
    waitpid($pid, 0);
    my $child_status = $? >> 8;
    my $out_len = length($output);
    log_msg("Error: child exit=$child_status, output=$out_len bytes") if $child_status != 0;
    if ($out_len > 0) {
        print $output;
    } else {
        log_msg("WARNING: empty output from child for $script");
        print "Status: 502 Bad Gateway\r\n";
        print "Content-Type: text/plain\r\n\r\n";
        print "Empty response from script\n";
    }
}

sub get_redis {
    state $redis;
    state $checked = 0;

    return $redis if $checked;
    $checked = 1;

    eval {
        $redis = Redis->new(
            server => sprintf('%s:%d', $redis_host, $redis_port),
            reconnect => 1,
            every => 2000,
            cnx_timeout => 1,
            read_timeout => 1,
            write_timeout => 1,
        );
    };

    if ($@) {
        log_msg("Redis connect failed: $@");
        $redis = undef;
    }

    return $redis;
}

sub restart_flag_is_newer {
    my ($started_at) = @_;
    my $redis = get_redis() or return 0;
    my $ts;

    eval {
        $ts = $redis->get($restart_flag_key);
    };
    if ($@) {
        log_msg("Cannot read restart flag from Redis: $@");
        return 0;
    }

    return 0 unless defined $ts && $ts ne '';
    return $ts > $started_at ? 1 : 0;
}
