package Core::Template;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub table { return 'templates' };

sub structure {
    return {
        id => '@',
        name => '?',
        title => '?',
        data => undef,
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
