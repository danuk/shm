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
            $_->{expired},
        );

        switch_user( $_->{user_id} );
        get_service('us', _id => $_->{user_service_id} )->touch;
    }

    return SUCCESS, { msg => 'successful' };
}

1;
