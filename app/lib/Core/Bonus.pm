package Core::Bonus;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Const;

sub table { return 'bonus_history' };

sub structure {
    return {
        id => {
            type => 'key',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        date => {
            type => 'now',
        },
        bonus => {
            type => 'number',
            required => 1,
        },
        comment => {
            type => 'json',
            value => undef,
        },
    }
}

1;
