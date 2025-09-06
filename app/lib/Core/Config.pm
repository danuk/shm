package Core::Config;
use v5.14;

use parent 'Core::Base';
use Core::Base;

our $config;
our $session_config;
require 'shm.conf';

sub table { return 'config' };

sub structure {
    return {
        key => {
            type => 'text',
            key => 1,
            title => 'ключ',
        },
        value => {
            type => 'json',
            required => 1,
            title => 'значение',
        },
    }
}

sub _id {
    my $self = shift;
    my %args = @_;

    if ( $args{key} ) {
        $self->{key} = $args{key};
        return "key=$self->{key}";
    }
    return undef;
}

sub table_allow_insert_key { return 1 };

sub validate_attributes {
    my $self = shift;
    my $method = shift;
    my %args = @_;

    my $report = get_service('report');

    unless ( $args{key} || $args{value} ) {
        $report->add_error('KeyOrValueNotPresent');
    }

    if ( $args{key} =~/^_/ ) {
        $report->add_error('KeyProhibited');
    }

    return $report->is_success;
}

sub file {
    my $self = shift;

    return {
        config => $config,
        session => $session_config,
    };
}

sub local {
    my $self = shift;
    my $section = shift;
    my $new_data = shift;

    if ( $new_data ) {
        $self->{config}->{local}->{ $section } = $new_data;
    }

    return $self->{config}->{local} unless $section;
    return $self->{config}->{local}->{ $section };
}

sub api_data_by_name {
    my $self = shift;
    my %args = (
        keys => undef,
        @_,
    );

    return $self->data_by_name( $args{key} );
}

sub data_by_name {
    my $self = shift;
    my $key = shift;

    my @list = $self->list( where => {
        $key ? ( key => $key ) : (),
    });

    my %ret = map{ $_->{key} => $_->{value} } @list;

    if ( $key ) {
        for ( keys %{ $ret{ $key } } ) {
            $ret{ $_ } = delete $ret{ $key }->{ $_ };
        }
        delete $ret{ $key };
    }

    return \%ret || {};
}

sub delete {
    my $self = shift;
    my %args = @_;

    my $report = get_service('report');

    if ( $self->id =~/^_/ ) {
        $report->add_error('KeyProhibited');
        return undef;
    }

    return $self->SUPER::delete( %args );
}

sub get_data {
    my $self = shift;

    my $config = $self->list(
        where => {
            key => $self->id,
        }
    );

    return $config->{ $self->id }->{value} || {};
}

sub list_for_api {
    my $self = shift;
    my %args = (
        key => undef,
        @_,
    );

    return $self->SUPER::list_for_api( where => {
            $args{key} ? ( key => $args{key} ) : (),
    });
}

sub set_value {
    my $self = shift;
    my $new_data = shift;

    return $self->set_json('value', $new_data );
}

1;

