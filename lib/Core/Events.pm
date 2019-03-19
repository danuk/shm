package Core::Events;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'events' };

sub structure {
    return {
        id => '@',
        kind => '?',
        name => '?',
        category => '?',    # www,mail,mysql
        event => '?',       # create,block,unblock...
        server_gid => '?',  # Group_id of servers
        params => { type => 'json', value => undef },
    }
}

sub get_events {
    my $self = shift;
    my %args = (
        kind => undef,
        category => undef,
        event => undef,
        @_,
    );

    my @res = $self->list(
        where => {
            $args{kind} ? ( kind => $args{kind} ) : (),
            $args{category} ? ( category => $args{category} ) : (),
            $args{event} ? ( event => $args{event} ) : (),
        },
    );
    return wantarray ? @res : \@res;
}

sub data {
    my $self = shift;

    unless ( $self->id && $self->{res} ) {
        get_service('logger')->error("Data not loaded");
    }
    return wantarray ? @{ $self->{res} } : $self->{res};
}

sub command {
    my $self = shift;
    return $self->data->{command};
}

sub exec {
    my $self = shift;
    my $args = {
        server_id => undef,
        data => undef,
        @_,
    };

    return get_service('spool')->push(
        server_id => $args->{server_id},
        cmd => $self->command,
        data => $args->{data},
    );
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        kind => undef,
        @_,
    );

    if ( $args{kind} ) {
        $args{where} = { kind => $args{kind} };
    }

    my @arr = $self->SUPER::list_for_api( %args );
    return @arr;
}


1;
