package Core::Transport::Ssh;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;
use Net::OpenSSH;
use POSIX qw(:signal_h WNOHANG);
use POSIX ":sys_wait_h";
use POSIX 'setsid';

sub send {
    my $self = shift;
    my $task = shift;

    my %server;
    if ( my $server = $task->server( transport => 'ssh' ) ) {
        %server = $server->get;
    } else {
        return SUCCESS, {
            error => "Server not defined",
        }
    }

    return $self->exec(
        %{ $server{settings} || () },
        host => $server{host},
        key_id => $task->server->key_id,
        cmd => $task->event->{settings}->{cmd},
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        stdin => $task->event->{settings}->{stdin} || $server{settings}->{stdin},
        $task ? ( task => $task->{res} ) : (),
    );
}

sub exec {
    my $self = shift;
    my %args = (
        host => undef,
        port => 22,
        key_id => undef,
        timeout => 10,
        cmd => undef,
        template_id => undef,
        usi => undef,
        stdin => undef,
        task => undef,
        event_name => undef,
        wait => 1,
        pipeline_id => undef,
        shell => $ENV{SHM_TEST} ? 'echo' : 'bash -e -v -c',
        proxy_jump => undef,
        @_,
    );

    my $event_name = $args{event_name};
    if ( $args{taks} && $args{task}->event ) {
        $event_name = $args{task}->event->{name};
    }

    if ( $args{template_id} ) {
        if ( my $template = get_service('template', _id => $args{template_id} ) ) {
            $args{cmd} ||= 'bash';
            $args{stdin} = $template->parse(
                %args,
                event_name => $event_name,
            );
        }
        else {
            get_service('report')->add_error('Template not found: ' . $args{template_id});
            return undef;
        }
    } elsif ( $args{cmd} ) {
        my $parser = get_service('template');
        $args{cmd} = $parser->parse(
            data => $args{cmd},
            %args,
        );

        if ( $args{stdin} ) {
            $args{stdin} = $parser->parse(
                data => $args{stdin},
                %args,
            );
            $args{stdin} ||= '*STDIN_EMPTY*';
        }
    }


    my $fork_mode = 0;
    my ($pid, $ret_code, $child_dbh);

    unless ( $args{wait} ) {
        unless ( $args{pipeline_id} ) {
            logger->error("Error: Can't use `no_wait` flag without `pipeline_id`");
            exit 1;
        }

        unless (defined ($pid = fork)) {
            die "cannot fork: $!";
        }
        $fork_mode = 1;
    }

    unless ( $args{pipeline_id} ) {
        # Auto create new pipe only for not fork mode
        # We cannot create auto pipelines in fork mode due to the transactional model of the database.
        $args{pipeline_id} = get_service('console')->new_pipe;
    }

    my $console = get_service('console', _id => $args{pipeline_id} );

    unless ( $pid ) {
        if ( $fork_mode ) {
            # I'm a child
            POSIX::setsid();
            unless ( $ENV{DEBUG} ) {
                open(STDOUT,">/dev/null");
                open(STDERR,">/dev/null");
            }
            alarm(0);

            # Create own db connection
            $child_dbh = $self->dbh_new();
        }

        my $host_msg = "Trying connect to: $args{host}";
        $host_msg .= " through $args{proxy_jump}" if $args{proxy_jump};

        logger->debug('SSH: ' . $host_msg );
        $console->append( $host_msg . "... ");

        my $key_file = get_service( 'Identities', _id => $args{key_id} )->private_key_file;

        $Net::OpenSSH::debug = ~0 if $ENV{DEBUG};

        my $ssh = Net::OpenSSH->new(
            $args{host},
            port => $args{port},
            key_path => $key_file,
            passphrase => undef,
            batch_mode => 1,
            timeout => $args{timeout},
            kill_ssh_on_timeout => 1,
            strict_mode => 0,
            master_opts => [-o => "StrictHostKeyChecking=no" ],
            $args{proxy_jump} ? (
                proxy_command => "ssh -o StrictHostKeyChecking=no -i $key_file -W %h:%p $args{proxy_jump}"
            ) : (),
        );
        unlink $key_file;

        if ( $ssh->error ) {
            logger->warning( $ssh->error );
            $console->append("FAIL\n".$ssh->error."\n");
            $ret_code = -1;
        } else {
            $console->append("SUCCESS\n\n");

            my @commands;
            push @commands, split('\s+', @args{shell} ) if $args{shell};
            push @commands, ref $args{cmd} eq 'ARRAY' ? join("\n", @{ $args{cmd} } ) : $args{cmd};

            my $out;
            my ($in, $rout, undef, $ssh_pid) = $ssh->open_ex(
                {
                    stdin_pipe => ( $args{stdin} ? 1 : 0 ),
                    stdout_pipe => 1,
                    stderr_to_stdout => 1,
                    tty => ( $args{stdin} ? 0 : 1 ),
                },
                @commands,
            ) or die "pipe_out method failed: " . $ssh->error;

            if ( $args{stdin} ) {
                print $in $args{stdin};
                close $in;
            }

            while (<$rout>) {
                $out .= $_;
                $console->append( $_ );
            }
            close $rout;

            my $ssh_kid = waitpid $ssh_pid, 0;
            $ret_code = $?>>8;
        }

        if ( $ret_code ) {
            $console->append("ERROR $ret_code\n\n");
        }
        else {
            $console->append("\n\nDONE\n\n");
        }

        $console->set_eof();

        if ( $fork_mode ) {
            $child_dbh->disconnect;
            exit $ret_code;
        }
    }

    if ( $ret_code == 0 ) {
        logger->debug("SSH CMD: $args{cmd}" );
        logger->debug("SSH RET_CODE: $ret_code");
    }
    elsif ( defined $ret_code ) {
        logger->warning("SSH CMD: $args{cmd}" );
        logger->warning("SSH RET_CODE: $ret_code");
    }

    return ( !defined($ret_code) ||  $ret_code == 0 ) ? SUCCESS : FAIL, {
        server => {
            host => $args{host},
            port => $args{port},
            key_id => $args{key_id},
        },
        command => $args{cmd},
        ret_code => $ret_code,
        pipeline_id => $args{pipeline_id},
    };
}

1;
