package Core::Template;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'templates' };

sub structure {
    return {
        id => '@',
        name => '?',
        title => '?',
        data => undef,
        settings => { type => 'json', value => undef },
    }
}


1;
