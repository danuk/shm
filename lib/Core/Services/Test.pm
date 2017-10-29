package Core::Services::Test;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub _id { return 'Services::Test' };

sub data_for_transport {
    my $self = shift;
    my %args = (
        task => undef,
        @_,
    );

    return SUCCESS, {
        payload => {
            message => 'This test payload',
        },
        cmd => 'test create',
    };
}

sub transport_responce_data {
    my $self = shift;
    return SUCCESS;
}

1;
