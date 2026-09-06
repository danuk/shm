package Core::Jobs;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw(
    now
    add_period
);

sub job_prolongate {
    my $self = shift;
    my $task = shift;

    return undef, { error => 'This task must be run under admin' } unless $self->user->authenticated->is_admin;
    my $spool = get_service('spool');

    my @arr = get_service('UserService')->list_expired_services( admin => 1 );

    for ( @arr ) {
        say sprintf("%d %d %s %s",
            $_->{user_id},
            $_->{user_service_id},
            $_->{created},
            $_->{expire},
        );

        delete $_->{settings}; # do not save settings into event

        $spool->add(
            user_id => $_->{user_id},
            prio => 50,
            event => {
                name => 'SYSTEM',
                title => 'user service prolongate event',
                kind => 'Jobs',
                method => 'job_prolongate_event',
                task_id => $task->id,
            },
            settings => {
                %{ $_ },
            },
        );
    }

    return SUCCESS, { msg => 'successful', affected_count => scalar @arr };
}

sub job_prolongate_event {
    my $self = shift;
    my $task = shift;

    unless ( $task && $task->settings && $task->settings->{user_service_id} ) {
        return undef, { error => 'No user_service_id in settings' };
    }

    my $us = $self->user->us->id( $task->settings->{user_service_id} );
    unless ( $us->lock() ) {
        return FAIL, { error => 'UserService is locked' };
    }
    $us->touch;
    $us->commit;

    return SUCCESS, { msg => 'successful' };
}

sub job_cleanup {
    my $self = shift;
    my $task = shift;

    get_service('us')->cleanup()->commit();
    get_service('SpoolHistory')->cleanup(); #auto commit
    get_service('Sessions')->cleanup(); # auto commit
    get_service('Statistics')->cleanup()->commit();
    get_service('Logs::Api')->cleanup(); # auto commit

    return SUCCESS, { msg => 'successful' };
}

sub job_make_forecasts {
    my $self = shift;
    my $task = shift;

    return undef, { error => 'This task must be run under admin' } unless $self->user->authenticated->is_admin;

    my $check_period = '1d';
    my %settings;

    if ( $task ) {
        $settings{days_before_notification} = $task->settings->{days} || $task->settings->{days_before_notification};
        $settings{blocked} = $task->settings->{blocked};

        if ( $task->settings->{check_period} =~ /^\d+[dmyHM]$/ ) {
            $check_period = $task->settings->{check_period};
        }
    }

    my $spool = get_service('spool');

    my @affected;
    my $user_candidates = $self->user->pays->forecast_candidates(
        distinct_users => 1,
        $settings{days_before_notification} ? ( days => $settings{days_before_notification} ) : (),
        $settings{blocked} ? ( blocked => $settings{blocked} ) : (),
    );

    for my $u ( @$user_candidates ) {
        $spool->add(
            user_id => $u->{user_id},
            prio => 110,
            event => {
                name => 'SYSTEM',
                title => 'user forecast event',
                kind => 'Jobs',
                method => 'job_make_forecast_event',
                task_id => $task->id,
            },
            settings => {
                check_period => $check_period,
                days         => $settings{days_before_notification},
                blocked      => $settings{blocked},
            },
        );

        push @affected, $u->{user_id};
    }
    return SUCCESS, { msg => 'successful', user_matches => \@affected };
}

sub job_make_forecast_event {
    my $self = shift;
    my $task = shift;

    my $u = $self->user;
    unless ( $u->lock() ) {
        return FAIL, { error => 'User is locked' };
    }

    my $check_period = $task && $task->settings->{check_period} || '1d';

    if ( my $last_check_date = $u->get_settings->{forecast}->{last_check_date} ) {
        my $next_check_date = add_period( $last_check_date, $check_period );
        if ( now() lt $next_check_date ) {
            $self->logger->info("Пропускаем forecast для " . $u->id . ": следующий forecast разрешен после $next_check_date");
            return SUCCESS, { msg => 'skipped' };
        }
    }

    my $ret = $u->pays->forecast(
        $task->settings->{days}    ? ( days    => $task->settings->{days}    ) : (),
        $task->settings->{blocked} ? ( blocked => $task->settings->{blocked} ) : (),
    );

    $u->set_settings({
        forecast => {
            last_check_date => now(),
        },
    });

    $u->make_event( 'forecast', settings => { forecast => $ret } ) if $ret->{total};
    return SUCCESS, { msg => 'successful ('. $ret->{total} .')' };
}

sub job_users {
    my $self = shift;
    my $task = shift;

    return undef, { error => 'This task must be run under admin' } unless $self->user->authenticated->is_admin;

    my %settings = (
        %{ $task->event_settings },
        %{ $task->settings },
    );

    my @users = $self->user->list(
        where => {
            $settings{user_id} ? ( user_id => $settings{user_id} ) : (),
        },
    );

    my $spool = get_service('spool');
    for my $user ( @users ) {
        $spool->add(
            user_id => $user->{user_id},
            prio => $settings{prio} || $task->get_prio || 100,
            event => {
                name => 'TASK',
                title => $task->event->{title},
                server_gid => $task->event->{server_gid},
                task_id => $task->id,
            },
            settings => \%settings,
        );
    }
    return SUCCESS, { msg => 'successful' };
}

1;
