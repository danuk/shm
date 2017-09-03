package Core::App;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'apps' };

sub structure {
    return {
        id => '@',
        user_id => '!',
        user_service_id => '?',
        name => '?',
        domain_id => undef,
        data => { type => 'json', value => undef },
    }
}


1;
