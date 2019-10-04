package Core::Pay;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'pays_history' };

sub structure {
    return {
        id => '@',
        user_id => '!',
        pay_system_id => '?',
        money => '?',
        date => 'now',
        comment => undef,
    }
}

sub pays {
    my $self = shift;
    my %args = (
        start => undef,
        stop => undef,
        limit => undef,
        @_,
    );

    my @vars;
    my $query = $self->query_select(    vars => \@vars,
                                        user_id => $self->user_id,
                                        range => { field => 'date', start => $args{start}, stop => $args{stop} },
                                        calc => 1,
                                        in => { $self->get_table_key => $self->res_by_arr },
                                        %{$args{limit}},
    );

    my $res = $self->query( $query, @vars );
    return $self unless $res;

    $self->{res} = $res;
    return $self;
}

sub add {
    my $self = shift;
    my %args = @_;

    if ( my $res = $self->SUPER::add( %args ) ) {
        get_service('user')->payment( money => $args{money} );
        return $res;
    }
    return undef;
}

sub list_for_api {
    my $self = shift;
    my @arr = $self->SUPER::list_for_api( @_ );

    return @arr;
}

1;
