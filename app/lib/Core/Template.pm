package Core::Template;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'templates' };

sub structure {
    return {
        id => {
            type => 'key',
        },
        name => {
            type => 'text',
            required => 1,
        },
        title => {
            type => 'text',
            required => 1,
        },
        data => {
            type => 'text',
        },
        settings => { type => 'json', value => undef },
    }
}

sub parsed {
    my $self = shift;
    my %args = (
        usi => undef,
        @_,
    );

    my $data = $self->get->{data} || return '';

    my $parser = get_service("parser");

    return $parser->parse(
        $data,
        %args,
    );

}

1;
