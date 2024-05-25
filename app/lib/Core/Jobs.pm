package Core::Jobs;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub job_prolongate {
    my $self = shift;

    my @arr = $self->srv('UserService')->list_expired_services( admin => 1 );

    for ( @arr ) {
        say sprintf("%d %d %s %s",
            $_->{user_id},
            $_->{user_service_id},
            $_->{created},
            $_->{expire},
        );

        my $user = $self->user->id( $_->{user_id} );
        next unless $user && $user->lock( timeout => 1 );

        $user->srv('us', _id => $_->{user_service_id} )->touch;
    }

    return SUCCESS, { msg => 'successful' };
}

sub job_cleanup {
    my $self = shift;
    my $task = shift;

    my $days = $task->event_settings->{days} || 10;
    my @arr = $self->srv('us')->list_for_delete( days => $days );;

    for ( @arr ) {
        say sprintf("%d %d %s %s",
            $_->{user_id},
            $_->{user_service_id},
            $_->{created},
            $_->{expire},
        );

        my $user = $self->user->id( $_->{user_id} );
        next unless $user && $user->lock( timeout => 1 );

        $user->srv('us', _id => $_->{user_service_id} )->delete;
    }

    return SUCCESS, { msg => 'successful' };
}

sub job_make_forecasts {
    my $self = shift;
    my $task = shift;

    my @users = $self->user->_list(
        where => {
            block => 0,
        },
    );

    for my $u ( @users ) {
        my $user = $self->user->id( $u->{user_id} );
        my $ret = $user->srv('pay')->forecast(
            $task->settings->{days_before_notification} ? ( days => $task->settings->{days_before_notification} ) : (),
        );
        next unless $ret->{total};
        next if $ret->{total} <= $u->{balance} + $u->{bonus} + $u->{credit};

        $user->make_event( 'forecast' );
    }
    return SUCCESS, { msg => 'successful' };
}

sub job_users {
    my $self = shift;
    my $task = shift;

    my %settings = (
        %{ $task->event_settings },
        %{ $task->settings },
    );

    my $user = $self->user;

    my @users = $user->_list(
        where => {
            block => 0,
            $settings{user_id} ? ( user_id => $settings{user_id} ) : (),
        },
    );

    for ( @users ) {
        $user->id( $_->{user_id} )->srv('spool')->add(
            event => {
                title => $task->event->{title},
                server_gid => $task->event->{server_gid},
            },
            settings => \%settings,
        );
    }
    return SUCCESS, { msg => 'successful' };
}

1;
