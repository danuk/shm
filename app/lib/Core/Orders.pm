package Core::Orders;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'invoices' };

sub structure {
    return {
        id => {
            type => 'number',
            key => 1,
        },
        date => {
            type => 'date',
            required => 1,
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        total => {
            type => 'number',
            required => 1,
        },
        text => {
            type => 'text',
        },
    }
}


1;
