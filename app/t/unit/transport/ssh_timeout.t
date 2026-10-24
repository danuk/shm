use v5.14;
use warnings;
use strict;

use Test::More;
use File::Temp qw(tempfile);
use POSIX ();
use Core::Const qw(SUCCESS FAIL);
use Core::Transport::Ssh;

{
    package SSHTimeoutTest::Console;
    sub new { bless { log => '' }, shift }
    sub append { $_[0]->{log} .= $_[1] }
    sub set_eof { $_[0]->{eof} = 1 }
}

{
    package SSHTimeoutTest::Identity;
    sub new { bless { path => $_[1] }, shift }
    sub private_key_file { $_[0]->{path} }
}

{
    package SSHTimeoutTest::Template;
    sub parse { my ($self, %args) = @_; return $args{data} }
}

{
    package SSHTimeoutTest::Logger;
    sub new { bless {}, shift }
    sub debug { }
    sub warning { }
}

sub run_case {
    my ($behavior) = @_;
    my ($key_fh, $key_path) = tempfile('shm-ssh-timeout-XXXX', TMPDIR => 1, UNLINK => 0);
    close $key_fh;

    my $console = SSHTimeoutTest::Console->new;
    my $identity = SSHTimeoutTest::Identity->new($key_path);
    my $template = bless {}, 'SSHTimeoutTest::Template';
    my $logger = SSHTimeoutTest::Logger->new;
    my $transport = bless {}, 'Core::Transport::Ssh';

    my ($status, $result);
    {
        no warnings qw(redefine once);
        local *Core::Transport::Ssh::get_service = sub {
            my ($name) = @_;
            return $console if $name eq 'console';
            return $identity if $name eq 'Identities';
            return $template if $name eq 'template';
            die "Unexpected service: $name";
        };
        local *Core::Transport::Ssh::logger = sub { $logger };
        local *Core::Transport::Ssh::get_ssh_host = sub {
            return defined $_[0] ? 'root@127.0.0.1' : undef;
        };
        local *Net::OpenSSH::new = sub { bless {}, 'Net::OpenSSH' };
        local *Net::OpenSSH::error = sub { undef };
        local *Net::OpenSSH::open_ex = sub {
            my ($read_fh, $write_fh);
            pipe($read_fh, $write_fh) or die "pipe failed: $!";
            my $pid = fork();
            defined $pid or die "fork failed: $!";
            if ($pid == 0) {
                close $read_fh;
                if ($behavior eq 'timeout') {
                    sleep 10; # parent must kill this child when alarm fires
                    POSIX::_exit(99);
                }
                if ($behavior eq 'signal') {
                    kill 'TERM', $$;
                    POSIX::_exit(99);
                }
                close $write_fh;
                POSIX::_exit($behavior eq 'error' ? 7 : 0);
            }
            close $write_fh;
            return (undef, $read_fh, undef, $pid);
        };

        my $exec = sub {
            ($status, $result) = $transport->exec(
                host => '127.0.0.1',
                key_id => 1,
                cmd => 'unused',
                shell => 'echo',
                timeout => $behavior eq 'timeout' ? 1 : 3,
                pipeline_id => 1,
            );
        };
        if ($behavior eq 'unwaitable') {
            local $SIG{CHLD} = 'IGNORE'; # auto-reap child: waitpid returns -1
            $exec->();
        } else {
            $exec->();
        }
    }

    unlink $key_path if -e $key_path;
    return ($status, $result, $console, $transport);
}

subtest 'successful exit' => sub {
    my ($status, $result, $console) = run_case('success');
    is($status, SUCCESS, 'transport returns SUCCESS');
    is($result->{ret_code}, 0, 'exit code 0 preserved');
    like($console->{log}, qr/DONE/, 'console reports DONE');
};

subtest 'nonzero exit' => sub {
    my ($status, $result) = run_case('error');
    is($status, FAIL, 'transport returns FAIL');
    is($result->{ret_code}, 7, 'exit code 7 preserved');
};

subtest 'terminated by signal' => sub {
    my ($status, $result, $console) = run_case('signal');
    is($status, FAIL, 'SIGTERM must not be SUCCESS');
    is($result->{ret_code}, 143, 'SIGTERM encoded as 128 + 15');
    unlike($console->{log}, qr/DONE/, 'console must not report DONE');
};

subtest 'SSH command timeout' => sub {
    my ($status, $result, $console, $transport) = run_case('timeout');
    is($status, FAIL, 'timeout returns FAIL');
    is($result->{ret_code}, 124, 'timeout returns code 124');
    is($transport->ret_code, 124, 'ret_code accessor reflects timeout');
    like($console->{log}, qr/TIMEOUT/, 'console reports TIMEOUT');
    unlike($console->{log}, qr/DONE/, 'console must not report DONE');
};

subtest 'waitpid failure' => sub {
    my ($status, $result, $console) = run_case('unwaitable');
    is($status, FAIL, 'waitpid error returns FAIL');
    is($result->{ret_code}, 125, 'waitpid error returns code 125');
    unlike($console->{log}, qr/DONE/, 'console must not report DONE');
};

done_testing();
