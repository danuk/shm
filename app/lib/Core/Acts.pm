package Core::Acts;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'acts' };

sub structure {
    return {
        act_id => {
            type => 'number',
            key => 1,
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        date => {
            type => 'date',
            required => 1,
        },
        show_act => {
            type => 'number',
            default => 1,
        },
    }
}

1;
