package Core::DomainServices;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'domains_services' };

sub structure {
    return {
        id => {
            type => 'number',
            key => 1,
        },
        domain_id => {
            type => 'number',
            required => 1,
        },
        user_service_id => {
            type => 'number',
            required => 1,
        },
        created => {
            type => 'now',
        },
    }
}


1;
