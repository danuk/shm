package Core::Transport::Ssh;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Net::OpenSSH;
use JSON;
use File::Temp;

sub send {
    my $self = shift;
    my %args = (
        server_id => undef, # for autoload server
        ip => undef,
        host => undef,
        user => 'ssm',
        private_key => undef,
        private_key_file => get_service('config')->global->{ssh_default_ssm_key},
        port => 22,
        timeout => 10,
        payload => undef,
        cmd => undef,
        @_,
    );

    my %server = (
        defined $args{server_id} ? ( %{ get_service('server', _id => $args{server_id} )->get } ) : (),
        map( $args{$_} ? ($_ => $args{$_}) : (), keys %args ),
    );

    my $data = $server{payload}->{payload};
    my $cmd = $server{payload}->{cmd} || $args{cmd};
    $cmd = join(' ', @args{ qw/category event/ } ) unless $cmd;

    my $key_file = $server{private_key_file};

    if ( $server{private_key} ) {
        my $tmp_fh = File::Temp->new( UNLINK => 1, SUFFIX => '.key' );
        say $tmp_fh $server{private_key};
        $tmp_fh->seek( 0, SEEK_END );
        $key_file = $tmp_fh->filename;
    }

    $server{host}//= $server{ip};
    my $host = join('@', $server{user}, $server{host} );

    get_service('logger')->debug('SSH: trying connect to ' . $host );

    my $ssh = Net::OpenSSH->new(
        $host,
        port => $server{port},
        key_path => $key_file,
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

    my $stdin_data = $data ? to_json( $data ) : undef;

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
