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

    my $cmd = $task->make_cmd_string( $args{cmd} || $task->event->{params}->{cmd} );
    my $stdin_data = $task->make_cmd_string( $task->event->{params}->{stdin} || $server{params}->{payload} );

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
        @_,
    );

    get_service('logger')->debug('SSH: trying connect to ' . $args{host} );
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
        get_service('logger')->warning( $ssh->error );
        return FAIL, {
            error => $ssh->error,
            ret_code => 1,
        };
    }

    my @shell_cmd = shellwords( $args{cmd} );

    my ( $out, $err ) = $ssh->capture2(
        {
            tty => 0,
            timeout => 10,
            stdin_data => $args{stdin_data},
        },
        @shell_cmd,
    );
    my $ret_code = $?>>8;

    if ( $ret_code == 0 ) {
        get_service('logger')->debug("SSH RET_CODE: $ret_code");
        get_service('logger')->debug("SSH STDIN: $args{stdin_data}");
        get_service('logger')->debug("SSH CMD: $args{cmd}" );
    }
    else {
        get_service('logger')->warning("SSH RET_CODE: $ret_code");
        get_service('logger')->warning("SSH STDIN: $args{stdin_data}");
        get_service('logger')->warning("SSH CMD: $args{cmd}" );
    }

    if ( $err ) {
        chomp $err;
        get_service('logger')->warning("SSH STDERR: $err");
    }

    my $data;

    if ( $ret_code == 0 ) {
        eval { $data = JSON->new->relaxed->decode( $out ); 1 };
        $data//= $out;
        chomp $data;
    }

    return $ret_code == 0 ? SUCCESS : FAIL, {
        server => {
            host => $args{host},
            port => $args{port},
            key_id => $args{key_id},
        },
        command => [ @shell_cmd ],
        ret_code => $ret_code,
        stdout => $data,
        stderr => $err,
    };
}

1;
