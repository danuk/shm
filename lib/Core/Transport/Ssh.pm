package Core::Transport::Ssh;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;
use Net::OpenSSH;
use JSON;
use Text::ParseWords 'shellwords';

sub send {
    my $self = shift;
    my $task = shift;
    my %args = (
        server_id => undef, # for autoload server
        event => {},
        port => 22,
        timeout => 10,
        payload => undef,
        cmd => undef,
        @_,
    );

    my %server = (
        $task->server->get,
        map( $args{$_} ? ($_ => $args{$_}) : (), keys %args ),
    );

    my $parser = get_service('parser');

    my $cmd = $parser->parse( $args{cmd} || $task->event->{params}->{cmd} );
    my $stdin_data = $parser->parse( $task->event->{params}->{stdin} || $server{params}->{payload} );

    return $self->exec(
        host => $server{host},
        key_id => $task->server->key_id,
        cmd => $cmd,
        stdin_data => $stdin_data,
        %{ $server{params} || () },
    );
}

sub exec {
    my $self = shift;
    my %args = (
        host => undef,
        port => 22,
        key_id => undef,
        timeout => 3,
        cmd => undef,
        stdin_data => undef,
        wait => 1,
        pipeline_id => undef,
        @_,
    );

    my @shell_cmd = shellwords( $args{cmd} );

    my $pid;
    unless (defined ($pid = fork)) {
        die "cannot fork: $!";
    }

    unless ( $pid ) {
        # I'm child
        # Create own db connection
        my $config = get_service('config');
        my $dbh = Core::Sql::Data::db_connect( %{ $config->global->{database} } );
        $config->local('dbh', $dbh );

        open(STDOUT,">/dev/null");
        open(STDERR,">/dev/null");
        POSIX::setsid();

        logger->debug('SSH: trying connect to ' . $args{host} );
        my $ssh = Net::OpenSSH->new(
            $args{host},
            port => $args{port},
            key_path => get_service( 'Identities', _id => $args{key_id} )->private_key_file,
            passphrase => undef,
            batch_mode => 1,
            timeout => $args{timeout},
            kill_ssh_on_timeout => 1,
            strict_mode => 0,
            master_opts => [-o => "StrictHostKeyChecking=no" ],
        );

        if ( $ssh->error ) {
            logger->warning( $ssh->error );
            return FAIL, {
                error => $ssh->error,
                ret_code => 1,
            };
        }

        my $out;
        my ($rout, $pid) = $ssh->pipe_out(
            {},
            @shell_cmd
        ) or die "pipe_out method failed: " . $ssh->error;

        my $console;
        while (<$rout>) {
            $out .= $_;

            if ( $args{pipeline_id} ) {
                $console ||= get_service('console', _id => $args{pipeline_id} );
                $console->append( $_ );
                print $_;
            }
        }

        $console->set_eof();

        close $rout;
        exit 0;
    }

    if ( $args{wait} ) {
        waitpid $pid, 0;
    } else {
        return SUCCESS, { pid => $pid };
    }

    my $ret_code = $?>>8;

    if ( $ret_code == 0 ) {
        logger->debug("SSH RET_CODE: $ret_code");
        logger->debug("SSH STDIN: $args{stdin_data}");
        logger->debug("SSH CMD: $args{cmd}" );
    }
    else {
        logger->warning("SSH RET_CODE: $ret_code");
        logger->warning("SSH STDIN: $args{stdin_data}");
        logger->warning("SSH CMD: $args{cmd}" );
    }

    my $data;

#    if ( $ret_code == 0 ) {
#        eval { $data = JSON->new->relaxed->decode( $out ); 1 };
#        $data//= $out;
#        chomp $data;
#    }

    return $ret_code == 0 ? SUCCESS : FAIL, {
        server => {
            host => $args{host},
            port => $args{port},
            key_id => $args{key_id},
        },
        command => [ @shell_cmd ],
        ret_code => $ret_code,
        stdout => $data,
    };
}

1;
