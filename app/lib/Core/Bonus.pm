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

sub amount {
    my $self = shift;
    return $self->get_bonus;
}

sub api_add {
    my $self = shift;
    my %args = (
        @_,
    );

    my $bonus_id = $self->user->set_bonus( %args );

    return $self->id( $bonus_id )->get;
}

1;
