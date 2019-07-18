package Core::Events;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'events' };

sub structure {
    return {
        id => '@',
        kind => '?',
        title => '?',
        name => '?',       # create,block,unblock...
        server_gid => '?',  # Group_id of servers
        params => { type => 'json', value => undef },
    }
}

sub get_events {
    my $self = shift;
    my %args = (
        kind => undef,
        name => undef,
        category => undef,
        @_,
    );

    my @res = $self->list(
        where => {
            $args{kind} ? ( kind => $args{kind} ) : (),
            $args{name} ? ( name => $args{name} ) : (),
            $args{category} ? ( 'params->category' => $args{category} ) : (),
        },
    );
    return wantarray ? @res : \@res;
}

sub make {
    my $self = shift;
    my %args = @_;

    get_service('spool')->add(
        @_,
    );
}

sub data {
    my $self = shift;

    unless ( $self->id && $self->{res} ) {
        logger->error("Data not loaded");
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
        id => undef,
        @_,
    );

    $args{where} = {
        $args{id} ? ( $self->get_table_key => $args{id} ) : (),
        $args{kind} ? ( kind => $args{kind} ) : (),
    };

    my @arr = $self->SUPER::list_for_api( %args );
    return @arr;
}


1;
