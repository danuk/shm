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
use Core::Utils qw( html_escape );

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

    return $self->exec(
        %server,
        %{ $server{settings} },
        %{ $task->event_settings },
        task => $task,
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
    );
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
        shell => $ENV{SHM_TEST} ? 'echo' : 'bash -c',
        proxy_jump => undef,
        @_,
    );

    my $event_name = $args{event_name};
    if ( $args{task} && $args{task}->event ) {
        $event_name //= $args{task}->event->{name};
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

    $args{pipeline_id} //= get_service('console')->new_pipe;

    my $console = get_service('console', _id => $args{pipeline_id} );

    my $host_msg = "Trying connect to: $args{host}";
    $host_msg .= " through $args{proxy_jump}" if $args{proxy_jump};

    logger->debug('SSH: ' . $host_msg );
    $console->append( "<font color=yellow>$host_msg ... </font>" );

    my $key_file = get_service( 'Identities', _id => $args{key_id} )->private_key_file;

    $Net::OpenSSH::debug = ~0 if $ENV{DEBUG};

    my $ret_code;
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
        $console->append("<font color=red>FAIL\n".$ssh->error."</font>\n");
        $ret_code = -1;
    } else {
        $console->append("<font color=green>SUCCESS</font>\n\n");

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
            $console->append( html_escape($_) );
        }
        close $rout;

        my $ssh_kid = waitpid $ssh_pid, 0;
        $ret_code = $?>>8;
    }

    if ( $ret_code ) {
        $console->append('<font color="red">ERROR '. $ret_code .'</font>');
    }
    else {
        $console->append('<font color="green">DONE</font>');
    }

    $console->set_eof();

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
            id => $args{server_id},
            host => $args{host},
            port => $args{port},
            key_id => $args{key_id},
        },
        cmd => $args{cmd},
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

1;
