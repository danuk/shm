package Core::Storage;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    encode_json
    decode_json
);

use SHM qw(print_header);

sub table { return 'storage' };

sub structure {
    return {
        user_id => {
            type => 'number',
            auto_fill => 1,
            key_mul => 1,
            title => 'id пользователя',
        },
        name => {
            type => 'text',
            key => 1,
            title => 'имя ключа',
        },
        created => {
            type => 'text',
            title => 'дата создания',
            readOnly => 1,
        },
        user_service_id => {
            type => 'number',
            title => 'id услуги пользователя',
        },
        data => {
            type => 'text',
            title => 'данные',
        },
        settings => { type => 'json', value => {} },
    }
}

sub table_allow_insert_key { return 1 };

sub add {
    my $self = shift;
    return $self->_add_or_replace('add', @_);
}

sub replace {
    my $self = shift;
    return $self->_add_or_replace('set', @_);
}

sub _add_or_replace {
    my $self = shift;
    my $method = shift;
    my %args = (
        name => undef,
        PUTDATA => undef,
        POSTDATA => undef,
        @_,
    );

    my $data;

    if ( ref $args{data} ) {
        $data = encode_json( $args{data} );
        $args{settings}->{json} = 1;
    } else {
        $data = delete $args{ PUTDATA } || delete $args{ POSTDATA };
        if ( $ENV{CONTENT_TYPE} =~/application\/json/i ) {
            unless ( decode_json( $data ) ) {
                get_service('report')->add_error("Incorrect JSON data: $data");
                return undef;
            }
            $args{settings}->{json} = 1;
        }
    }

    unless ( $args{name} ) {
        get_service('report')->add_error("Name is required");
        return undef;
    }

    if ( $method eq 'add' ) {
        my $id = $self->SUPER::add(
            data => $data,
            %args,
        );

        unless ( $id ) {
            get_service('report')->add_error("Can't save the data. Perhaps the record already exists?");
            return undef;
        }
    } elsif ( $method eq 'set' ) {
        $self = $self->id( $args{name} ) || return undef;
        $self->_set(
            data => $data,
            where => {
                user_id => $self->user_id,
                name => $args{name},
            },
        );
    }

    $self->{res}->{data} = $args{data};

    return {
        result => 'successful',
        length => length( $data ),
    };
}

# method for templates
sub save {
    my $self = shift;
    my $name = shift;
    my $data = shift;

    $self->delete( name => $name );

    my $id = $self->SUPER::add(
        name => $name,
        data => $data,
        settings => {
            ref $data ? ( 'json' => 1 ) : (),
        },
    );

    return $data;
}

# method for templates
sub load {
    my $self = shift;
    my $name = shift;

    return $self->read( name => $name );
}

# method for templates
sub del {
    my $self = shift;
    my $name = shift;

    return $self->delete( name => $name );
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

sub list_for_api {
    my $self = shift;

    my @data = $self->SUPER::list_for_api( @_ );
    delete $_->{data} for @data;

    return @data;
}

sub read {
    my $self = shift;
    my %args = (
        name => undef,
        decode_json => 1,
        @_,
    );

    my $self = $self->id( $args{name} );
    return undef unless $self;

    return $self->data( decode_json => $args{decode_json} );
}

sub get {
    my $self = shift;
    my %args = @_;

    $self->SUPER::get( %args ) || return '';
    $self->data(); # convert data to json if json

    return wantarray ? %{ $self->{res} } : $self->{res};
}

sub data {
    my $self = shift;
    my %args = (
        decode_json => 1,
        @_,
    );

   if ( $args{decode_json} && $self->get_settings->{json} ) {
        my $data = $self->get_data;
        unless ( ref $data ) {
            if ( my $json = decode_json( $data ) ) {
                $self->{res}->{data} = $json;
            }
        }
    } else {
        utf8::decode( $self->{res}->{data} );
    }
    return $self->get_data;
}

sub download {
    my $self = shift;
    my %args = (
        name => 'file.bin',
        @_,
    );

    print_header(
        'Content-Type' => 'binary/octet-stream',
        'Content-Disposition' => 'attachment; filename=' . $args{name},
    );

    return $self->read( %args, decode_json => 0 );
}

1;
