package Core::Jobs;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

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

        my $user = $self->user->id( $_->{user_id} );
        next unless $user->lock( timeout => 1 );

        $user->us->id( $_->{user_service_id} )->touch;
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

        my $user = $self->user->id( $_->{user_id} );
        next unless $user->lock( timeout => 1 );

        $user->us->id( $_->{user_service_id} )->delete;
    }

    return SUCCESS, { msg => 'successful' };
}

sub job_make_forecasts {
    my $self = shift;
    my $task = shift;

    my %settings;
    if ( $task ) {
        $settings{days_before_notification} = $task->settings->{days_before_notification};
        $settings{blocked} = $task->settings->{blocked};
    }

    my $users = $self->user->items;

    my @affected;
    for my $u ( @$users ) {
        my $ret = $u->pays->forecast(
            $settings{days_before_notification} ? ( days => $settings{days_before_notification} ) : (),
            $settings{blocked} ? ( blocked => $settings{blocked} ) : (),
        );
        next unless $ret->{total};

        $u->make_event( 'forecast' );
        push @affected, $u->id,
    }
    return SUCCESS, { msg => 'successful', user_matches => \@affected };
}

sub job_users {
    my $self = shift;
    my $task = shift;

    my %settings = (
        %{ $task->event_settings },
        %{ $task->settings },
    );

    my $users = $self->user->items(
        where => {
            $settings{user_id} ? ( user_id => $settings{user_id} ) : (),
        },
    );

    for my $user ( @$users ) {
        $user->srv('spool')->add(
            prio => 100,
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
