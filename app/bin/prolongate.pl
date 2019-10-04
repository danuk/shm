#!/usr/bin/perl

use v5.14;
use SHM;
use Core::System::ServiceManager qw( get_service );
use Core::Billing;
use Core::Utils;

SHM->new( skip_check_auth => 1 );

for ( get_service('UserService')->list_expired_services( admin => 1 ) ) {

    say sprintf("%d %d %s %s",
        $_->{user_id},
        $_->{user_service_id},
        $_->{created},
        $_->{expired},
    );

    switch_user( $_->{user_id} );
    get_service('USObject', _id => $_->{user_service_id} )->touch();
}

exit 0;
