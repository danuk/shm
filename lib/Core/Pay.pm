package Core::Pay;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'pays_history' };

sub structure {
    return {
        pay_id => '@',
        user_id => '!',
        from_user_id => '?',
        money => '?',
        date => 'now',
        who => '?',
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
                                        user_id => $self->{user_id},
                                        range => { field => 'date', start => $args{start}, stop => $args{stop} },
                                        calc => 1,
                                        in => { pay_id => $self->res_by_arr },
                                        %{$args{limit}},
    );

    my $res = $self->query( $query, @vars );
    return $self unless $res;

    $self->{res} = $res;
    return $self;
}

1;
