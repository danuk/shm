package Core::Template;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Template;

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

sub parse {
    my $self = shift;
    my %args = (
        usi => undef,
        data => undef,
        @_,
    );

    my $data = $args{data} || $self->data || return '';

    my $vars = {
        user => get_service('user'),
        $args{usi} ? ( us => get_service('us', _id => $args{usi}) ) : (),
        config => get_service('config')->data_by_name,
    };

    my $template = Template->new({
        INTERPOLATE  => 1,
        PRE_CHOMP => 1,
    });

    my $result = "";
    unless ($template->process( \$data, $vars, \$result )) {
        logger->warning("Template rander error: ", $template->error() );
        return '';
    }

    return $result;
}

1;
