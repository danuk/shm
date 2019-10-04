package Core::ActsData;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'acts_data' };

sub structure {
    return {
        id => '@',
        act_id => undef,
        user_id => '!',
        service_id => undef,
        user_service_id => undef,
        withdraw_id => undef,
        amount => '?',
        name => undef,
        start_date => undef,
        stop_date => undef,
    }
}


1;
