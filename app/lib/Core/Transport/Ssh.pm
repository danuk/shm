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
use Core::Utils qw(
    html_escape
    is_host
    encode_utf8
);

sub events {
    return {
        'exec' => {
            event => {
                title => 'Execute ssh command',
                kind => 'Transport::Ssh',
                method => 'send',
                settings => {},
            },
        },
    };
}

sub send {
    my $self = shift;
    my $task = shift;
    my %server;

    if ( my $server = $task->server ) {
        %server = $server->get;
    }

    my @ret = $self->exec(
        %server,
        %{ $server{settings} },
        %{ $task->event_settings },
        %{ $task->settings },
        task => $task,
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
    );

    return @ret;
}

sub exec {
    my $self = shift;
    my %args = (
        host => undef,
        port => 22,
        key_id => undef,
        server_id => undef,
        timeout => 10,
        cmd => undef,
        template_id => undef,
        usi => undef,
        stdin => undef,
        task => undef,
        event_name => undef,
        pipeline_id => undef,
        shell => $ENV{SHM_TEST} ? 'echo' : undef,
        stderr_to_stdout => 1,
        proxy_jump => undef,
        @_,
    );

    my $event_name = $args{event_name};
    if ( $args{task} && $args{task}->event ) {
        $event_name //= $args{task}->event->{name};
    }

    my $host = get_ssh_host( $args{host} );
    unless ( $host ) {
        get_service('report')->add_error("Incorrect ssh host: $host");
        return undef, {
            error => "Incorrect ssh host: $args{host}",
        };
    }

    my $proxy_jump = get_ssh_host( $args{proxy_host} );

    if ( $args{template_id} ) {
        if ( my $template = get_service('template', _id => $args{template_id} ) ) {
            delete $args{cmd};
            $args{shell} //= 'bash';
            $args{stdin} = $template->parse(
                %args,
                event_name => $event_name,
            );
            unless ( $args{stdin} ) {
                return SUCCESS, {
                    msg => "Template `$args{template_id}` is empty. Nothing to do. Skip it.",
                };
            }
        }
        else {
            get_service('report')->add_error("Template not found: $args{template_id}");
            return undef, {
                error => "Template not found: $args{template_id}",
            };
        }
    } elsif ( $args{cmd} ) {
        $args{shell} //= 'bash -c';
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
        }
    } else {
        get_service('report')->add_error("Nothing to do (no cmd, no template_id)");
        return undef, {
            error => "Nothing to do (no cmd, no template_id)",
        };
    }

    $args{pipeline_id} //= get_service('console')->new_pipe;

    my $console = get_service('console', _id => $args{pipeline_id} );
    unless ( $console ) {
        get_service('report')->add_error("Console not found: $args{pipeline_id}");
        return undef, {
            error => "Console not found: $args{pipeline_id}",
        };
    }

    my $host_msg = "Trying connect to: $host (timeout: $args{timeout}s)";
    $host_msg .= " port $args{port}";
    $host_msg .= " through $proxy_jump" if $proxy_jump;

    logger->debug('SSH: ' . $host_msg );
    $console->append( "<font color=yellow>$host_msg ... </font>" );

    my $key_file;
    if ( my $ident = get_service( 'Identities', _id => $args{key_id} ) ) {
        $key_file = $ident->private_key_file;
    } else {
        return undef, {
            error => sprintf('Identities with id: %s not exists', $args{key_id}),
        };
    }

    $Net::OpenSSH::debug = ~0 if $ENV{DEBUG} eq 'DEBUG';

    my $ret_code;
    my $ssh = Net::OpenSSH->new(
        $host,
        port => $args{port},
        key_path => $key_file,
        passphrase => undef,
        batch_mode => 1,
        timeout => $args{timeout},
        kill_ssh_on_timeout => 1,
        strict_mode => 0,
        master_opts => [-o => "StrictHostKeyChecking=no" ],
        $proxy_jump ? (
            proxy_command => "ssh -o StrictHostKeyChecking=no -i $key_file -W %h:%p $proxy_jump"
        ) : (),
    );
    unlink $key_file;

    if ( $ssh->error ) {
        logger->error( $ssh->error );
        $console->append("<font color=red>FAIL\n".$ssh->error."</font>\n");
        $ret_code = -1;
    } else {
        $console->append("<font color=green>SUCCESS</font>\n\n");

        my @commands;
        push @commands, split('\s+', @args{shell} ) if $args{shell};
        push @commands, (ref $args{cmd} eq 'ARRAY' ? join("\n", @{ $args{cmd} } ) : $args{cmd} ) if $args{cmd};

        my $out;
        my ($in, $rout, undef, $ssh_pid) = $ssh->open_ex(
            {
                stdin_pipe => ( $args{stdin} ? 1 : 0 ),
                stdout_pipe => 1,
                stderr_to_stdout => $args{stderr_to_stdout},
                tty => ( $args{stdin} ? 0 : 1 ),
            },
            @commands,
        ) or die "pipe_out method failed: " . $ssh->error;

        if ( $args{stdin} ) {
            print $in encode_utf8( $args{stdin} );
            close $in;
        }

        eval {
            local $SIG{ALRM} = sub { die "timeout\n" };
            alarm($args{timeout} || 10);
            while (<$rout>) {
                $out .= $_;
                $console->append( html_escape($_) );
            }
            alarm(0);
        };
        if ($@ && $@ eq "timeout\n") {
            kill 'TERM', $ssh_pid if $ssh_pid;
            $console->append('<font color="red">TIMEOUT</font><br/>');
        }
        close $rout;

        my $ssh_kid = waitpid $ssh_pid, 0;
        $ret_code = $?>>8;
    }

    if ( $ret_code ) {
        logger->error("ERROR: $ret_code");
        $console->append('<font color="red">ERROR '. $ret_code .'</font>');
    }
    else {
        $console->append('<font color="green">DONE</font>');
    }

    $console->set_eof();

    if ( $ret_code == 0 ) {
        logger->debug("SSH CMD: $args{cmd}" ) if $args{cmd};
        logger->debug("SSH RET_CODE: $ret_code");
    }
    elsif ( defined $ret_code ) {
        logger->error("SSH CMD: $args{cmd}" ) if $args{cmd};
        logger->error("SSH RET_CODE: $ret_code");
    }

    $ret_code //= 0;
    return ( $ret_code == 0 ) ? SUCCESS : FAIL, {
        server => {
            id => $args{server_id},
            host => $args{host},
            port => $args{port},
            key_id => $args{key_id},
        },
        $args{template_id} ? (template_id => $args{template_id} ) : ( cmd => $args{cmd}),
        ret_code => $ret_code,
        pipeline_id => $args{pipeline_id},
    };
}

sub ssh_test {
    my $self = shift;
    my $args = {
        host => undef,
        key_id => undef,
        server_id => undef,
        cmd => 'uname',
        event_name => 'test',
        pipeline_id => get_service('console')->new_pipe,
        @_,
    };

    $self->make_event( 'exec',
        settings => {
            server_id => delete $args->{server_id},
        },
        event => {
            title => 'Run TEST script',
            settings => $args,
        },
    );

    return $args;
}

sub ssh_init {
    my $self = shift;
    my $args = {
        host => undef,
        key_id => undef,
        server_id => undef,
        template_id => undef,
        event_name => 'init',
        pipeline_id => get_service('console')->new_pipe,
        @_,
    };

    $self->make_event( 'exec',
        settings => {
            server_id => delete $args->{server_id},
        },
        event => {
            title => 'Run INIT script',
            settings => $args,
        },
    );

    return $args;
}

sub get_ssh_host {
    my $host = shift;

    my ( $user, $host_name );
    if ( $host=~/@/ ) {
        ( $user, $host_name ) = split( /\@/, $host );
    }
    $host_name //= $host;

    if ( $user ) {
        unless ( $user=~/^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$/i ) {
            logger->warning('SSH user incorrect: ' . $user );
            return undef;
        }
    } else {
        $user = 'root';
    }

    unless ( is_host( $host_name ) ) {
        logger->warning('SSH host incorrect: ' . $host_name );
        return undef;
    }

    return sprintf("%s@%s", $user, $host_name );
}

1;

