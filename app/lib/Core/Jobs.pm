package Core::Jobs;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

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

    my $days = $task->event_settings->{days} || 10;
    my @arr = get_service('us')->list_for_delete( days => $days );;

    for ( @arr ) {
        say sprintf("%d %d %s %s",
            $_->{user_id},
            $_->{user_service_id},
            $_->{created},
            $_->{expire},
        );

        my $user = $self->user->id( $_->{user_id} );

        my $us = $user->us->id( $_->{user_service_id} );
        next unless $us->lock();
        $us->delete;
        $us->commit;
    }

    return SUCCESS, { msg => 'successful' };
}

sub job_make_forecasts {
    my $self = shift;
    my $task = shift;

    return undef, { error => 'This task must be run under admin' } unless $self->user->authenticated->is_admin;

    my %settings;
    if ( $task ) {
        $settings{days_before_notification} = $task->settings->{days} || $task->settings->{days_before_notification};
        $settings{blocked} = $task->settings->{blocked};
    }

    my $spool = get_service('spool');
    my $users = $self->user->items;

    my @affected;
    for my $u ( @$users ) {
        my $ret = $u->pays->forecast(
            $settings{days_before_notification} ? ( days => $settings{days_before_notification} ) : (),
            $settings{blocked} ? ( blocked => $settings{blocked} ) : (),
        );
        next unless $ret->{total};

        $spool->add(
            user_id => $u->id,
            prio => 110,
            event => {
                name => 'SYSTEM',
                title => 'user forecast event',
                kind => 'Jobs',
                method => 'job_make_forecast_event',
                task_id => $task->id,
            },
        );

        push @affected, $u->id,
    }
    return SUCCESS, { msg => 'successful', user_matches => \@affected };
}

sub job_make_forecast_event {
    my $self = shift;
    $self->user->make_event( 'forecast' );
    return SUCCESS, { msg => 'successful' };
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
