package Core::Acts;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'acts' };

sub structure {
    return {
        act_id => '@',
        user_id => '!',
        date => '?',
        show_act => 1,
    }
}

1;
