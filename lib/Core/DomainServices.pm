package Core::DomainServices;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'domains_services' };

sub structure {
    return {
        id => '@',
        domain_id => '?',
        user_service_id => '?',
        created => 'now',
    }
}


1;
