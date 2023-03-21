package Core::Jobs;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Core::Utils qw( switch_user );

sub job_prolongate {
    my $self = shift;

    my @arr = get_service('UserService')->list_expired_services( admin => 1 );

    for ( @arr ) {
        say sprintf("%d %d %s %s",
            $_->{user_id},
            $_->{user_service_id},
            $_->{created},
            $_->{expire},
        );

        my $user_id = $_->{user_id};
        next unless get_service('user', _id => $user_id )->lock( timeout => 1 );

        switch_user( $user_id );
        get_service('us',  user_id => $user_id, _id => $_->{user_service_id} )->touch;
    }

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

        my $user_id = $_->{user_id};
        next unless get_service('user', _id => $user_id )->lock( timeout => 1 );

        switch_user( $user_id );
        get_service('us',  user_id => $user_id, _id => $_->{user_service_id} )->delete;
    }

    return SUCCESS, { msg => 'successful' };
}

sub job_make_forecasts {
    my $self = shift;
    my $task = shift;

    my @users = get_service('user')->_list(
        where => {
            block => 0,
        },
    );

    my $spool = get_service('spool');
    my $pay = get_service('pay');

    for my $u ( @users ) {
        switch_user( $u->{user_id} );
        my $ret = $pay->forecast(
            $task->settings->{days_before_notification} ? ( days => $task->settings->{days_before_notification} ) : (),
        );
        next unless $ret->{total};
        next if $ret->{total} <= $u->{balance} + $u->{bonus} + $u->{credit};

        $self->make_event( 'forecast' );
    }
    return SUCCESS, { msg => 'successful' };
}

1;
