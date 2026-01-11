package Core::Cloud::Jobs;

use v5.14;
use parent 'Core::Cloud';
use Core::Base;
use Core::Const;

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
        chown 33, 33, PAY_SYSTEM_DIR or logger->error("Can't chown " . PAY_SYSTEM_DIR . ": $!");
    }

    $self->job_download_all_paystems();
}

sub job_download_all_paystems {
    my $self = shift;

    unless ( $self->get_auth_basic() ) {
        return undef;
    }

    my $spool = get_service('spool');

    for my $ps_name ( $self->ps_list ) {
        next if -f $self->ps_file_name( $ps_name );

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

    unless ( $self->get_auth_basic() ) {
        return SUCCESS, { msg => 'no auth' };
    }

    my $file = $self->ps_file_name( $ps_name );

    my $response = $self->cloud_request(
        url => '/service/paysystems/download',
        content => {
            ps => $ps_name,
            arch => $ps_arch,
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

    chmod 0755, $file;
    logger->info("Downloaded paysystem: $ps_name");

    return SUCCESS, { msg => "successful saved: $file" };
}

sub make_receipt {
    my $self = shift;
    my $task = shift;

    my $pay_id = $task->settings->{pay_id} || return;
    my $pay = $self->srv('Pay', _id => $pay_id ) || return;

    my $srv_customlab_nalog = $self->config->{pay_systems}->{srv_customlab_nalog} || return;
    return unless $srv_customlab_nalog->{enabled};

    # TODO:
    # use exec_local_file() from Utils.pm for safe execute srv_customlab_nalog
    # check execute status and make correct task answer.
    # For retry task use it: return FAIL, { error => 'error message' };

    return SUCCESS, { msg => 'successful' };
}


1;