package Core::Identities;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use File::Temp;
use Core::Utils qw(
    file_by_string
);

sub table { return 'identities' };

sub structure {
    return {
        id => '@',
        user_id => '!',
        name => '?',
        private_key => '?',
        public_key => undef,
        fingerprint => '?',
    }
}

sub add {
    my $self = shift;
    my %args = (
        name => undef,
        private_key => undef,
        @_,
    );

    $args{fingerprint} = $self->make_fingerprint( file_by_string( $args{private_key} ) );

    unless ( $args{fingerprint} ) {
        get_service('logger')->error("Can't create fingerprint.");
        return undef;
    }
    return $self->SUPER::add( %args );
}

sub make_fingerprint {
    my $self = shift;
    my $file = shift;

    my @ret = `ssh-keygen -E MD5 -lf $file 2>/dev/null`;

    if ( $? == 0 ) {
        chomp $ret[0];
        return $ret[0];
    }
    return undef;
}

sub private_key_file {
    my $self = shift;

    return file_by_string( $self->res->{private_key} );
}

sub generate_key_pair {


}

sub list_for_api {
    my $self = shift;
    my %args = (
        @_,
    );

    my @arr = $self->SUPER::list_for_api( %args );
    delete $_->{private_key} for @arr;

    return @arr;
}

1;
