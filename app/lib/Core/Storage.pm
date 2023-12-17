package Core::Storage;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    decode_json
);

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
        settings => { type => 'json', value => {} },
    }
}

sub add {
    my $self = shift;
    my %args = (
        name => undef,
        PUTDATA => undef,
        @_,
    );

    if ( $ENV{CONTENT_TYPE} =~/application\/json/i ) {
        if ( decode_json( $args{ PUTDATA } ) ) {
            $args{settings}->{json} = 1;
        }
    }

    my $id = $self->SUPER::add(
        data => delete $args{PUTDATA},
        %args,
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
        usi => undef,
        @_,
    );

    my ( $data ) = $self->SUPER::_delete(
        where => {
            user_id => $self->user_id,
            $args{name} ? ( name => $args{name} ) : (),
            $args{usi} ? ( user_service_id => $args{usi} ) : (),
        },
    );

    return undef;
}

sub list {
    my $self = shift;
    my %args = (
        user_id => undef,
        @_,
    );

    my $method = get_service('user')->authenticated->is_admin ? 'SUPER::_list' : 'SUPER::list';

    my @data = $self->$method(
        $args{user_id} ? ( user_id => $args{user_id} ) : (),
    );

    delete $_->{data} for @data;

    if ( wantarray ) {
        return @data;
    } else {
       return \@data;
    }
}

sub read {
    my $self = shift;
    my %args = (
        name => undef,
        @_,
    );

    my ( $data ) = $self->SUPER::list(
        where => {
            name => $args{name},
        },
    );

    return undef unless $data;

    if ( $data->{settings}->{json} ) {
        $data->{data} = decode_json( $data->{data} );
    }

    return $data->{data};
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
