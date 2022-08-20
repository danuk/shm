package Core::Storage;

use v5.14;
use parent 'Core::Base';
use Core::Base;

use SHM qw(print_header);

sub table { return 'storage' };

sub structure {
    return {
        user_id => {
            type => 'key',
            auto_fill => 1,
        },
        name => {
            type => 'text',
        },
        created => {
            type => 'text',
        },
        user_service_id => {
            type => 'number',
        },
        data => {
            type => 'text',
        },
        settings => { type => 'json', value => undef },
    }
}

sub add {
    my $self = shift;
    my %args = (
        name => undef,
        PUTDATA => undef,
        @_,
    );

    my $id = $self->SUPER::_add(
        user_id => $self->user_id,
        name => $args{name},
        data => $args{PUTDATA},
    );

    unless ( $id ) {
        get_service('report')->add_error("Can't save the data. Perhaps the record already exists?");
        return undef;
    }

    return {
        result => 'successful',
        length => length( $args{PUTDATA} ),
    };
}

sub delete {
    my $self = shift;
    my %args = (
        name => undef,
        @_,
    );

    my ( $data ) = $self->SUPER::_delete(
        where => {
            user_id => $self->user_id,
            name => $args{name},
        },
    );

    return undef;
}

sub list {
    my $self = shift;

    my @data = $self->_list(
        where => {
            user_id => $self->user_id,
        },
    );

    delete $_->{data} for @data;
    return \@data;
}

sub list_for_api {
    my $self = shift;
    my %args = (
        name => undef,
        @_,
    );

    my ( $data ) = $self->_list(
        where => {
            user_id => $self->user_id,
            name => $args{name},
        },
    );

    return $data->{data};
}

sub download {
    my $self = shift;
    my %args = (
        name => undef,
        @_,
    );

    print_header(
        'Content-Type' => 'binary/octet-stream',
        'Content-Disposition' => 'attachment; filename=' . $args{name},
    );

    return $self->list_for_api( %args );
}

1;
