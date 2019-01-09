package Core::Transport::Ssh;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;
use Net::OpenSSH;
use JSON;

sub send {
    my $self = shift;
    my $task = shift;
    my %args = (
        server_id => undef, # for autoload server
        event => {},
        user => 'ssm',
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

    my $cmd = $task->make_cmd_string( $args{cmd} || $task->event->{params}->{cmd} || $server{params}->{cmd} );
    my $stdin_data = $task->make_cmd_string( $task->event->{params}->{stdin} || $server{params}->{payload} );
 
    $server{host}//= $server{ip};
    my $host = join('@', $server{user}, $server{host} );

    get_service('logger')->debug('SSH: trying connect to ' . $host );

    my $ssh = Net::OpenSSH->new(
        $host,
        port => $server{port},
        key_path => $task->server->key_file,
        passphrase => undef,
        batch_mode => 1,
        timeout => $server{timeout},
        kill_ssh_on_timeout => 1,
        strict_mode => 0,
        master_opts => [-o => "StrictHostKeyChecking=no" ],
    );

    if ( $ssh->error ) {
        get_service('logger')->warning( $ssh->error );
        return FAIL, { error => $ssh->error };
    }

    my ( $out, $err ) = $ssh->capture2(
        {
            tty => 0,
            timeout => 10,
            stdin_data => $stdin_data,
        },
        split(' ', $cmd ),
    );
    my $ret_code = $?>>8;

    if ( $ret_code == 0 ) {
        get_service('logger')->debug("SSH RET_CODE: $ret_code");
        get_service('logger')->debug("SSH STDIN: $stdin_data");
        get_service('logger')->debug("SSH CMD: $cmd" );
    }
    else {
        get_service('logger')->warning("SSH RET_CODE: $ret_code");
        get_service('logger')->warning("SSH STDIN: $stdin_data");
        get_service('logger')->warning("SSH CMD: $cmd" );
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
        ret_code => $ret_code,
        data => $data,
        error => $err,
    };
}

1;
