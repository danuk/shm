package Core::Config;
use v5.14;

use parent 'Core::Base';
use Core::Base;

our $config;
our $session_config;
require 'shm.conf';

use Core::Utils qw(
    decode_json
);

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

# Кастомное имя сервиса. Не используем user_id в имени, так как сервис не зависит от пользователя
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

    if ( $args{key} =~/^_/ && not $self->user->authenticated->is_admin ) {
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
        key => undef,
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

sub api_data_by_company {
    my $self = shift;
    my $key = 'company';

    my @list = $self->list( where => {
        key => $key,
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

    return $self->dbh->do(
        "DELETE FROM config WHERE `key` = ?",
        undef,
        $self->id
    );
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
        filter => {},
        @_,
    );

    my $filter_by_value = delete $args{filter}->{value};

    if ( $args{key} ) {
        $args{where}->{key} = $args{key};
    }
    elsif ( $args{filter}->{key} ) {
        $args{where}->{key} = delete $args{filter}->{key};
    }
    $args{where}->{value} = { '-like' => $filter_by_value } if $filter_by_value;

    return $self->SUPER::list_for_api( %args );
}

sub api_set_value {
    my $self = shift;
    my %args = (
        key => undef,
        @_,
    );

    return undef unless $self->id;

    my $config = $self->id( $args{key} );
    unless ( $config ) {
        report->add_error( 'key not found' );
        return undef;
    }

    if ( my $new_values = decode_json $args{ POSTDATA } ) {
        my $old_values = $self->get;
        $config->set_value( $new_values );

        my $method = sprintf("updated_%s", $args{key} );
        if ( $self->can( $method ) ) {
            $self->$method( old_values => $old_values );
        }
    }
    return scalar $self->get;
}

sub api_delete_value {
    my $self = shift;
    my %args = (
        key => undef,
        value => undef,
        @_,
    );

    return undef unless $self->id;

    my $config = $self->id( $args{key} );
    unless ( $config ) {
        report->add_error( 'key not found' );
        return undef;
    }

    my $key = $self->get;
    my $old_values = $key->{value};

    delete $old_values->{ $args{value} };
    $config->set_value( $old_values );

    return scalar $self->get;
}

sub set_value {
    my $self = shift;
    my $new_data = shift;

    return $self->set_json('value', $new_data );
}

sub updated_pay_systems {
    my $self = shift;
    my %args = (
        old_values => undef,
        @_,
    );

    $self->srv('Cloud::Jobs')->job_download_all_paystems();
}

sub version_info {
    my $self = shift;
    my $report = get_service('report');

    my $version_file = "$ENV{SHM_ROOT_DIR}/version.json";

    unless ( -f $version_file ) {
        $report->add_error('VersionFileNotFound');
        return undef;
    }

    my $version_data = decode_json( Core::Utils::read_file( $version_file ) );

    return $version_data;
}

