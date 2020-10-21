package Core::Profile;

use v5.14;
use parent 'Core::Base';

sub table { return 'profiles' };

sub structure {
    return {
        id => {
            type => 'key',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        data => { type => 'json', value => undef },
        created => {
            type => 'now',
        },
    }
}

1;

