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

        switch_user( $_->{user_id} );
        get_service('us', _id => $_->{user_service_id} )->touch;
    }

    return SUCCESS, { msg => 'successful' };
}

sub job_make_forecasts {
    my $self = shift;
    my $task = shift;

    unless ($task->event_settings &&
            $task->event_settings->{template_id} &&
            $task->server_id ) {
        return FAIL, { error => 'template_id or server_id not defined' };
    }

    my @users = get_service('user')->_list(
        where => {
            block => 0,
        },
    );

    my $spool = get_service('spool');
    my $pay = get_service('pay');

    for ( @users ) {
        switch_user( $_->{user_id} );
        my $ret = $pay->forecast();
        next unless $ret->{total};

        $spool->push(
            user_id => $_->{user_id},
            event => {
                title => 'Send forecast to user',
                kind => 'Transport::Mail',
                settings => {
                    template_id => $task->event_settings->{template_id},
                    server_id => $task->server_id,
                },
            },
        );
    }
    return SUCCESS, { msg => 'successful' };
}

1;
