package Core::App;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'apps' };

sub structure {
    return {
        id => {
            type => 'key',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        user_service_id => {
            type => 'number',
            required => 1,
        },
        name => {
            type => 'text',
            required => 1,
        },
        domain_id => {
            type => 'number',
        },
        settings => {
            type => 'json',
            value => undef,
        },
    }
}


1;
