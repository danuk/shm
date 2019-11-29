package Core::Profile;

use v5.14;
use parent 'Core::Base';

sub table { return 'profiles' };

sub structure {
    return {
        id => '@',
        user_id => '!',
        data => { type => 'json', value => undef },
        created => 'now',
    }
}

1;

