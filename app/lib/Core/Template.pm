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
        task => undef,
        @_,
    );

    my $data = $args{data} || $self->data || return '';

    my $vars = {
        user => get_service('user'),
        $args{usi} ? ( us => get_service('us', _id => $args{usi}) ) : (),
        $args{task} ? ( task => $args{task} ) : (),
        config => get_service('config')->data_by_name,
    };

    my $template = Template->new({
        START_TAG => quotemeta('{{'),
        END_TAG   => quotemeta('}}'),
        ANYCASE => 1,
        INTERPOLATE  => 0,
        PRE_CHOMP => 1,
    });

    my $result = "";
    unless ($template->process( \$data, $vars, \$result )) {
        logger->warning("Template rander error: ", $template->error() );
        return '';
    }

    return $result;
}

sub list_for_api {
    my $self = shift;
    my %args = (
        id => undef,
        @_,
    );

    my $template = $self->id( delete $args{id} );

    unless ( $template ) {
        logger->warning("Template not found");
        get_service('report')->add_error('Template not found');
        return undef;
    }

    return scalar $template->parse( %args );
}

1;
