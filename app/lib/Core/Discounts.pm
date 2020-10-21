package Core::Discounts;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'discounts' };

sub structure {
    return {
        discount_id => {
            type => 'key',
        },
        title => {
            type => 'text',
            required => 1,
        },
        months => {
            type => 'number',
            required => 1,
        },
        percent => {
            type => 'number',
            required => 1,
        },
    }
}

sub get_by_period {
    my $self = shift;
    my $args = {
        months => undef,
        @_,
    };

    die 'Months required' unless defined $args->{months};

    my @ret = $self->list(
        range => { field => 'months', stop => $args->{months} },
        order => [ months => 'desc' ],
        limit => 1,
    );

    return $ret[0];
}

1;
