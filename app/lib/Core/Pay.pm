package Core::Pay;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'pays_history' };

sub structure {
    return {
        id => {
            type => 'key',
        },
        user_id => {
            type => 'number',
            auto_fill => 1,
        },
        pay_system_id => {
            type => 'number',
            default => 1,
        },
        money => {
            type => 'number',
            required => 1,
        },
        date => {
            type => 'now',
        },
        comment => {
            type => 'text',
        },
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

1;
