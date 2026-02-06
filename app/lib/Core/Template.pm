package Core::Template;

use v5.14;
use utf8;
use parent 'Core::Base';
use Core::Base;
use Core::Const;
use Template;
use File::Find qw(find);
use File::Basename;
use File::Path qw(make_path);

use Core::Utils qw(
    encode_json_perl
    encode_json
    decode_json
    parse_args
    parse_headers
    blessed
    encode_base64url
    decode_base64url
    to_query_string
    read_file
    write_file
);

my $dir = 'data/templates';

# Automatically create constants hash from Core::Const exports
sub _get_constants {
    my %constants;

    # Get all exported constants from Core::Const
    no strict 'refs';
    for my $const_name (@Core::Const::EXPORT) {
        if (defined &{"Core::Const::$const_name"}) {
            $constants{$const_name} = &{"Core::Const::$const_name"}();
        }
    }
    use strict 'refs';

    return \%constants;
}

sub init {
    my $self = shift;
    my %args = (
        @_,
    );

    $self->{file_mode} = 1 if -d $dir;
    return $self;
}

# fake
sub table { return 'templates' };

sub structure {
    return {
        id => {
            type => 'text',
            key => 1,
            title => 'имя шаблона',
        },
        data => {
            type => 'text',
            title => 'шаблон',
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
        get_smart_args( @_ ),
    );

    my $data = $args{data} || $self->data || return '';

    my (
        $pay_id,
        $bonus_id,
        $task_id,
    );

    my $task = delete $args{task};

    if ( $task && blessed( $task ) ) {
        $args{event_name} //= $task->event->{name};
        $pay_id = $task->get_settings->{pay_id};
        $bonus_id = $task->get_settings->{bonus_id};
        $task_id = $task->id,
    }

    my $vars = {
        user => sub { $self->srv('user', defined $_[0] ? (_id => $_[0]) : () ) },
        us => sub { $self->srv('us', _id => $args{usi} || $_[0] ) },
        $task ? ( task => $task ) : (),
        server => sub { $self->srv('server', _id => $args{server_id} || $_[0] ) },
        servers => sub { $self->srv('server') },
        sg => sub { $self->srv('ServerGroups', defined $_[0] ? (_id => $_[0]) : () ) },
        pay => sub { $self->srv('pay', _id => $pay_id || $_[0] ) },
        bonus => sub { $self->srv('bonus', _id => $bonus_id || $_[0] ) },
        wd => sub { $self->srv('withdraw', defined $_[0] ? (_id => $_[0]) : () ) },
        config => sub { $self->srv('config')->data_by_name },
        tpl => $self,
        service => sub { $self->srv('service', defined $_[0] ? (_id => $_[0]) : () ) },
        services => sub { $self->srv('service') },
        storage => sub { $self->srv('storage', defined $_[0] ? (_id => $_[0]) : () ) },
        telegram => sub { $self->srv('Transport::Telegram', task => $task) },
        tg_api => sub { encode_json_perl( shift, pretty => 1 ) }, # for testing templates
        response => { test_data => 1 },  # for testing templates
        http => sub { $self->srv('Transport::Http') },
        ssh => sub { $self->srv('Transport::Ssh') },
        mail => sub { $self->srv('Transport::Mail') },
        s3 => sub { $self->srv('S3') },
        spool => sub { $self->srv('Spool', $task_id ? (task_id => $task_id) : (), defined $_[0] ? (_id => $_[0]) : () ) },
        promo => sub { $self->srv('promo', defined $_[0] ? (_id => $_[0]) : () ) },
        misc => sub { $self->srv('misc') },
        logger => sub { $self->srv('logger') },
        report => sub { $self->srv('report') },
        cache => sub { $self->srv('Core::System::Cache') },
        currency => sub { $self->srv('Cloud::Currency') },
        $args{event_name} ? ( event_name => uc $args{event_name} ) : (),
        %{ $args{vars} }, # do not move it upper. It allows to override promo end others
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
            # for compatibility with other Cyrillic texts in the templates
            return encode_json_perl( $data );
        },
        fromJson => sub {
            my $data = shift;
            return decode_json( $data );
        },
        dump => sub {
            use Data::Dumper;
            return Dumper( @_ );
        },
        toQueryString => sub { to_query_string( shift ) },
        toBase64Url => sub { encode_base64url( shift ) },
        fromBase64Url => sub { decode_base64url( shift ) },

        # for filter()
        isNull => sub { return \'isNull' },
        isNotNull => sub { return \'isNotNull' },
        isEmpty => sub { return \'isEmpty' },
        isNotEmpty => sub { return \'isNotEmpty' },
        # Numeric comparisons
        lt => sub { return \('lt:' . ($_[0] // '')) },  # less than
        gt => sub { return \('gt:' . ($_[0] // '')) },  # greater than
        le => sub { return \('le:' . ($_[0] // '')) },  # less than or equal
        ge => sub { return \('ge:' . ($_[0] // '')) },  # greater than or equal
        eq => sub { return \('eq:' . ($_[0] // '')) },  # equal to
        ne => sub { return \('ne:' . ($_[0] // '')) },  # not equal to
        between => sub {
            my ($min, $max) = @_;
            return \("between:$min:$max") if defined $min && defined $max;
        },
        # Sign checks
        isPositive => sub { return \'isPositive' },  # greater than 0
        isNegative => sub { return \'isNegative' },  # less than 0
        isNonNegative => sub { return \'isNonNegative' },  # greater than or equal to 0
        isNonPositive => sub { return \'isNonPositive' },  # less than or equal to 0

        null => \'null',
        true => \'true',
        false => \'false',

        # Constants from Core::Const (automatically loaded directly)
        %{ _get_constants() },
    };

    my $template = Template->new({
        START_TAG => quotemeta( $args{START_TAG} ),
        END_TAG   => quotemeta( $args{END_TAG} ),
        ANYCASE => 1,
        INTERPOLATE  => 0,
        PRE_CHOMP => 1,
        EVAL_PERL => 1,
        INCLUDE_PATH => 'data/templates',
        #LOAD_TEMPLATES => [ $provider1 ],
    });

    my $result = "";
    unless ($template->process( \$data, $vars, \$result )) {
        my $err = "Template render error: " . $template->error();
        logger->error( $err );
        report->add_error( $err );

        if ( $task && blessed( $task ) ) {
            $task->answer(
                status => FAIL,
            );
        }
        return $err;
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
        report->add_error('Template not found');
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
        report->add_error('Template not found');
        return undef;
    }

    unless ( $template->get_settings->{allow_public} ) {
        logger->warning("Template not public");
        report->add_error('Permission denied: template is not public');
        return undef;
    }

    return $self->show( %args, do_not_parse => 0 );
}

sub read_dir_recursive {
    my @dirs = @_;
    my @files;
    find( {
            wanted => sub {
                for ( glob "\"$_/*.tpl\"" ) {
                    $_=~s/^\.\///;
                    $_=~s/^$dir\///;
                    $_=~s/\.tpl$//;
                    push @files, $_;
                };
            },
            no_chdir => 1
        }, @dirs
    );
    return @files;
}

sub read_template_from_file {
    my $file = sprintf("%s/%s.tpl", $dir, shift );
    my $data = read_file( $file );
    if ( ref $data ) {
        report->error( $file, $data->{error} );
        return undef;
    }

    utf8::decode( $data );
    return $data;
}

sub read_settings_from_file {
    my $file = sprintf("%s/%s.tpls", $dir, shift );
    my $data = read_file( $file );
    if ( ref $data ) {
        report->error( $file, $data->{error} ) if -f $file;
        return;
    }

    utf8::decode( $data );
    return $data;
}

sub write_template_to_file {
    my $template = shift;
    my $file = sprintf("%s/%s.tpl", $dir, $template );
    my $data = shift;
    my $settings = shift;
    my $ret = write_file( $file, $data );
    if ( ref $ret ) {
        report->error( $file, $ret->{error} );
        return;
    }

    if ( $settings ) {
        my $json = encode_json( $settings, pretty => 1 );
        my $file = sprintf("%s/%s.tpls", $dir, $template );
        my $ret = write_file( $file, $json );
        if ( ref $ret ) {
            report->error( $file, $ret->{error} );
            return;
        }
    }
    return 1;
}

sub _db_list {
    my $self = shift;
    my %args = (
        @_,
    );

    if ( my $id = $args{id} ) {
        $args{where}->{id} ||= $id;
    }

    if ( my $filter = delete $args{filter} ) {
        my $where = $self->query_for_filtering( %$filter );
        $args{where} = {
            %{ $args{where} || {} },
            %{ $where || {} },
        };
    }

    return $self->SUPER::_list( %args );
}

sub _list {
    my $self = shift;
    my %args = (
        @_,
    );

    return $self->_db_list( @_ ) unless $self->{file_mode};

    if ( my $filter = delete $args{filter} ) {
        my $where = $self->query_for_filtering( %$filter );
        $args{where} = { %{ $args{where} || {} }, %{ $where || {} } };
    }

    my @data;

    if ( my $id = $args{id} || $args{where}->{'templates.id'} ) {
        my $data = read_template_from_file( $id );
        push @data, {
            id => $id,
            data => $data,
            settings => decode_json( read_settings_from_file( $id )) || {},
        } if defined $data;
    } else {
        for ( $self->read_dir_recursive( $dir ) ) {
            push @data, {
                id => $_,
                settings => decode_json( read_settings_from_file( $_ )) || {},
            }
        }
        if ( my $where = $args{where} ) {
            my $id_filter_key = exists $where->{id} ? 'id' : exists $where->{'templates.id'} ? 'templates.id' : undef;

            if ( $id_filter_key ) {
                my $id_filter = $where->{$id_filter_key};

                if ( ref $id_filter eq 'HASH' && exists $id_filter->{'-like'} ) {
                    my $pattern = $id_filter->{'-like'};
                    $pattern =~ s/%/.*/g;
                    $pattern =~ s/_/./g;
                    @data = grep { $_->{id} =~ /$pattern/i } @data;
                }
                elsif ( !ref $id_filter ) {
                    @data = grep { $_->{id} eq $id_filter } @data;
                }
            }
        }
    }
    return wantarray ? @data : \@data;
}

sub _db_add {
    my $self = shift;
    my %args = (
        @_,
    );

    return $self->SUPER::add(
        %args,
        data => $args{data} || delete $args{PUTDATA},
    );
}

sub add {
    my $self = shift;
    my %args = (
        @_,
    );

    return $self->_db_add( @_ ) unless $self->{file_mode};

    my $id = $args{id};

    if ( -f sprintf("%s/%s.tpl", $dir, $id ) ) {
        report->error("File already exists");
        return 0;
    }

    # Create path
    my $path = dirname( $id );
    if ( $path ne '.') {
        make_path( "$dir/$path" );
    }

    $self->{res}->{id} = $id;
    return $self->set( %args );
}

sub _db_set {
    my $self = shift;
    my %args = (
        @_,
    );

    return $self->SUPER::set(
        %args,
        data => $args{data} || delete $args{POSTDATA},
    );
}

sub set {
    my $self = shift;
    my %args = (
        @_,
    );

    return $self->_db_set( @_ ) unless $self->{file_mode};

    $self->{res}->{data} = $args{data};
    $self->{res}->{settings} = $args{settings};

    write_template_to_file( $self->id, $args{data} || $args{PUTDATA} || $args{POSTDATA}, $args{settings} );
    return $self->id;
};

sub _delete {
    my $self = shift;
    my %args = (
        @_,
    );

    return $self->SUPER::_delete( @_ ) unless $self->{file_mode};

    my $template = sprintf("%s/%s.tpl", $dir, $args{id} );
    my $settings = sprintf("%s/%s.tpls", $dir, $args{id} );

    unless ( -f $template ) {
        report->error("Template not found");
        return 0;
    }

    unlink $template;
    unlink $settings;
    return 1;
}

1;
