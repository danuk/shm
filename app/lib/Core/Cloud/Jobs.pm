package Core::Cloud::Jobs;

use v5.14;
use parent 'Core::Cloud';
use Core::Base;
use Core::Const;
use Core::Utils qw(exec_local_file);
use Core::System::ServiceManager qw( get_service );

use constant PAY_SYSTEM_DIR => '/app/data/pay_systems';

sub ps_file_name {
    my $self = shift;
    my $ps_name = shift;

    return sprintf("%s/%s.cgi", PAY_SYSTEM_DIR, $ps_name );
}

sub startup {
    my $self = shift;

    unless ( -d PAY_SYSTEM_DIR ) {
        mkdir PAY_SYSTEM_DIR, 0755 or logger->error("Can't create directory " . PAY_SYSTEM_DIR . ": $!");
    }

    my @dir_stat = stat(PAY_SYSTEM_DIR);
    unless ( ($dir_stat[2] & 07777) == 0755 ) {
        chmod 0755, PAY_SYSTEM_DIR or logger->error("Can't chmod " . PAY_SYSTEM_DIR . ": $!");
    }
    unless ( $dir_stat[4] == 33 && $dir_stat[5] == 33 ) {
        chown 33, 33, PAY_SYSTEM_DIR or logger->error("Can't chown " . PAY_SYSTEM_DIR . ": $!");
    }

    $self->job_download_all_paystems();
}

sub job_download_all_paystems {
    my $self = shift;

    unless ( $self->get_auth_basic() ) {
        return undef;
    }

    my $config = get_service('config', _id => 'pay_systems');

    my $spool = get_service('spool');

    for my $ps_name ( $self->ps_list ) {

        my $need_update_to = $config->get_data->{ $ps_name }->{need_update_to};
        next if -f $self->ps_file_name( $ps_name ) && !$need_update_to;

        $spool->add(
            user_id => 1,
            prio => 1,
            event => {
                name => 'SYSTEM',
                title => 'download pay system: ' . $ps_name,
                kind => 'Cloud::Jobs',
                method => 'job_download_paystem',
            },
            settings => {
                ps_name => $ps_name,
                arch => $self->arch,
                $need_update_to ? ( version => $need_update_to ) : (),
            },
        );
    }

    return 1;
}

sub job_download_paystem {
    my $self = shift;
    my $task = shift;

    unless ( $task && $task->settings && $task->settings->{ps_name} ) {
        return undef, { error => 'No ps_name in settings' };
    }

    my $ps_arch = $task->settings->{arch} || $self->arch;
    my $ps_name = $task->settings->{ps_name};
    my $version = $task->settings->{version};

    unless ( $self->get_auth_basic() ) {
        return SUCCESS, { msg => 'no auth' };
    }

    my $file = $self->ps_file_name( $ps_name );

    my $response = $self->cloud_request(
        url => '/service/paysystems/download',
        content => {
            ps => $ps_name,
            arch => $ps_arch,
            $version ? ( version => $version ) : (),
        }
    );

    unless ( $response ) {
        return FAIL, { error => 'http response is empty' };
    }

    if ( $response->code == 403 || $response->code == 404 ) {
        return SUCCESS, { error => $response->decoded_content  };
    }

    unless ( $response->is_success ) {
        my $err = $response->decoded_content;
        logger->error( $err );
        return FAIL, { error => $err };
    }

    my $content = $response->decoded_content;
    unless ( $content ) {
        return FAIL, { error => 'http content is empty' };
    }

    open my $fh, '>', $file or do {
        my $err = "Can't create file $file: $!";
        logger->error( $err );
        return FAIL, { error => $err };
    };

    print $fh $content;
    close $fh;

    my @file_stat = stat($file);
    unless ( $file_stat[4] == 33 && $file_stat[5] == 33 ) {
        chown 33, 33, $file or logger->error("Can't chown " . $file . ": $!");
    }
    unless ( ($file_stat[2] & 07777) == 0755 ) {
        chmod 0755, $file or logger->error("Can't chmod " . $file . ": $!");
    }

    my $config = get_service('config', _id => 'pay_systems');
    if ( my $version = $config->get_data->{ $ps_name }->{need_update_to} ) {
        $config->set_value({
            $ps_name => {
                version => $version,
                need_update_to => undef,
            },
        });
    };

    logger->info("Downloaded paysystem: $ps_name");

    return SUCCESS, { msg => "successful saved: $file" };
}

sub make_receipt {
    my $self = shift;
    my $task = shift;

    my $srv_customlab_nalog = get_service('config')->id( 'pay_systems' )->get_data->{'srv_customlab_nalog'} || {};
    unless ( $srv_customlab_nalog && $srv_customlab_nalog->{enabled} ) {
        return SUCCESS, { msg => 'srv_customlab_nalog is not enabled, skipping receipt' };
    }

    my $ps_file = $self->ps_file_name('srv_customlab_nalog');
    unless ( -f $ps_file ) {
        return SUCCESS, { msg => "SHMCustomlab_nalog is not found" };
    }

    my $pay_id = $task->settings->{pay_id};
    my $result = exec_local_file(
        cmd => [ $ps_file, 'action=send', "pay_id=$pay_id" ],
        timeout => 60,
    );

    if ( $result->{error} ) {
        return FAIL, { error => $result->{error} };
    }

    unless ( $result->{success} ) {
        return FAIL, {
            error => 'Failed to send receipt',
            output => $result->{output},
            exit_code => $result->{exit_code},
        };
    }

    return SUCCESS, { msg => 'successful', output => $result->{output} };
}


1;
