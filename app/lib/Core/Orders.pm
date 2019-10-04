package Core::Orders;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'invoices' };

sub structure {
    return {
        id => '@',
        date => '?',
        user_id => '!',
        total => '?',
        text => undef,
    }
}


1;
