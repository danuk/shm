package Core::Template;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Template;

use Core::Utils qw(
    encode_json
    parse_args
    parse_headers
    blessed
);

sub table { return 'templates' };

sub structure {
    return {
        id => {
            type => 'key',
        },
        data => {
            type => 'text',
        },
        settings => { type => 'json', value => {} },
    }
}

sub parse {
    my $self = shift;
    my %args = (
        usi => undef,
        data => undef,
        task => undef,
        server_id => undef,
        event_name => undef,
        vars => {},
        START_TAG => '{{',
        END_TAG => '}}',
        @_,
    );

    my $data = $args{data} || $self->data || return '';

    my (
        $pay_id,
        $bonus_id,
    );

    if ( $args{task} && blessed( $args{task} ) ) {
        $args{event_name} //= $args{task}->event->{name};
        $pay_id = $args{task}->get_settings->{pay_id};
        $bonus_id = $args{task}->get_settings->{bonus_id};
    }

    my $vars = {
        user => sub { get_service('user') },
        us => sub { get_service('us', _id => $args{usi}) },
        $args{task} ? ( task => $args{task} ) : (),
        server => sub { get_service('server', _id => $args{server_id}) },
        servers => sub { get_service('server') },
        sg => sub { get_service('ServerGroups') },
        pay => sub { get_service('pay', _id => $pay_id) },
        bonus => sub { get_service('bonus', _id => $bonus_id) },
        wd => sub { get_service('withdraw') },
        config => sub { get_service('config')->data_by_name },
        tpl => $self,
        service => sub { get_service('service') },
        services => sub { get_service('service') },
        storage => sub { get_service('storage') },
        telegram => sub { get_service('Transport::Telegram', task => $args{task}) },
        http => sub { get_service('Transport::Http') },
        spool => sub { get_service('Spool') },
        spool_history => sub { get_service('SpoolHistory') },
        $args{event_name} ? ( event_name => uc $args{event_name} ) : (),
        %{ $args{vars} },
        request => sub {
            my %params = parse_args();
            my %headers = parse_headers();

            return {
                params => \%params,
                headers => \%headers,
            };
        },
        ref => sub {
            my $data = shift;
            return ref $data eq 'HASH' ? [ $data ] : ( $data || [] );
        },
        toJson => sub {
            my $data = shift;
            return encode_json( $data );
        },
        toQueryString => sub {
            my $data = shift;
            return '' if ref $data ne 'HASH';

            use URI::Escape;
            my @ret;
            for ( keys %{ $data } ) {
                push @ret, sprintf("%s=%s", $_, uri_escape( $data->{ $_ } ));
            }
            return join('&', @ret );
        },
    };

    my $template = Template->new({
        START_TAG => quotemeta( $args{START_TAG} ),
        END_TAG   => quotemeta( $args{END_TAG} ),
        ANYCASE => 1,
        INTERPOLATE  => 0,
        PRE_CHOMP => 1,
        EVAL_PERL => 1,
    });

    my $result = "";
    unless ($template->process( \$data, $vars, \$result )) {
        my $report = get_service('report');
        $report->add_error( '' . $template->error() );
        logger->error("Template render error: ", $template->error() );
        return '';
    }

    $result =~s/^(\s+|\n|\r)+//;
    $result =~s/(\s+|\n|\r)+$//;

    return $result;
}

sub show {
    my $self = shift;
    my %args = (
        id => undef,
        do_not_parse => 0,
        @_,
    );

    my $template = $self->id( delete $args{id} );

    unless ( $template ) {
        logger->warning("Template not found");
        get_service('report')->add_error('Template not found');
        return undef;
    }

    if ( $args{do_not_parse} ) {
        return $template->get->{data};
    } else {
        return scalar $template->parse( %args );
    }
}

sub show_public {
    my $self = shift;
    my %args = (
        id => undef,
        @_,
    );

    my $template = $self->id( $args{id} );
    unless ( $template ) {
        logger->warning("Template not found");
        get_service('report')->add_error('Template not found');
        return undef;
    }

    unless ( $template->get_settings->{allow_public} ) {
        logger->warning("Template not public");
        get_service('report')->add_error('Permission denied: template is not public');
        return undef;
    }

    return $self->show( %args, do_not_parse => 0 );
}

sub add {
    my $self = shift;
    my %args = (
        @_,
    );

    return $self->SUPER::add(
        %args,
        data => $args{data} || delete $args{PUTDATA},
    );
}

sub set {
    my $self = shift;
    my %args = (
        @_,
    );

    return $self->SUPER::set(
        %args,
        data => $args{data} || delete $args{POSTDATA},
    );
}

1;
