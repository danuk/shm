package Core::ActsData;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'acts_data' };

sub structure {
    return {
        id => {
            type => 'key',
        },
        act_id => {
            type => 'number',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        service_id => {
            type => 'number',
        },
        user_service_id => {
            type => 'number',
        },
        withdraw_id => {
            type => 'number',
        },
        amount => {
            type => 'number',
            required => 1,
        },
        name => {
            type => 'text',
        },
        start_date => {
            type => 'date',
        },
        stop_date => {
            type => 'date',
        },
    }
}


1;
