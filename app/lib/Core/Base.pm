package Core::Base;

use v5.14;
use utf8;
use parent qw(
    Core::Sql::Data
    Core::System::Service
);
use Core::System::ServiceManager qw( get_service logger );
use Core::Sql::Data;
use Carp qw(confess);
use Data::Dumper;
use Core::Utils qw(
    hash_merge
    encode_json
    dots_str_to_sql
    get_user_ip
    is_ip_allowed
);
$Data::Dumper::Deepcopy = 1;

our @EXPORT = qw(
    get_service
    Dumper
    confess
    logger
    report
    cache
    get_smart_args
    first_item
);

use vars qw($AUTOLOAD);
sub DESTROY {}; # ignore destroy destructor
sub AUTOLOAD {
    my $self = shift;

    if ( $AUTOLOAD =~ /^.*::(get_)?(\w+)$/ ) {
        my $method = $2;

        unless ( %{ $self->res } ) {
            # load data if not loaded before
            $self->get if $self->can('structure');
        }

        return $self->res->{ $method } if defined $self->res->{ $method };

        if ( $self->can('structure') ) {
            my $structure = $self->structure;
            return $structure->{ $method }->{value}; # return default value from struct
        }
        return undef;
    } else {
        confess ("Method not exists: " . $AUTOLOAD );
    }
}

sub new_obj {
    my $proto = shift;
    my $res = shift;

    my $class = ref( $proto ) || $proto;
    my $ref = {
        user_id => $res->{user_id} || $proto->user_id,
        res => $res,
    };

    my $self = bless $ref, $class;

    if ( $self->can('init') ) {
        return $self->init();
    }
    return $self;
}

sub new {
    my $proto = shift;
    my $args = {
        _id => undef,
        @_,
    };
    my $class = ref($proto) || $proto;
    my $self = bless( $args, $class );

    $self->init( %$args ) if $self->can('init');

    # Устанавливаем идентификатор автоматически
    if ( $class->can('structure') ) {
        my $key = $class->get_table_key;
        $args->{ $key } //= delete $args->{_id};

        # Выходим если не смогли загрузить данные по идентификатору
        if ( defined $args->{ $key } && not exists $args->{res} ) {
            return undef unless $self->get;
        }
    }

    return $self;
}

sub id {
    my $self = shift;
    my $id = shift;

    if ( defined $id ) {
        return $self->srv( ref $self, _id => $id, user_id => $self->user_id );
    }

    my $key_field = $self->get_table_key;
    my $id = $self->{ $key_field };
    $id //= $self->res->{ $key_field };

    unless (length $id) {
        logger->debug('identifier not defined for class ' . ref $self);
        return undef;
    }

    if ( $self->can('structure') ) {
        my $structure = $self->structure;
        if ( my $type = $structure->{ $key_field }->{type} ) {
            if ( $type eq 'number' ) {
                $id = $id + 0;
            } elsif ( $type eq 'text' ) {
                $id = "$id";
            }
        }
    }

    return $id;
}

sub user_id {
    my $self = shift;
    return $self->res->{user_id} || $self->{user_id} || get_service('config')->local->{user_id};
}

sub user {
    my $self = shift;
    my $user_id = shift || $self->user_id;
    return get_service('user', _id => $user_id );
}

sub res {
    my $self = shift;
    my $res = shift;

    unless ( $res ) {
        $self->{res}//={};
        return wantarray ? %{ $self->{res} } : $self->{res};
    }

    if ( ref $res ne 'HASH' ) {
        logger->fatal("Can't set SCALAR data to resource");
    }

    $self->{res} = $res;
    return $self;
}

sub filter {
    my $self = shift;
    my %args = (
        get_smart_args( @_ ),
    );

    unless ( %args ) {
        $self->{filter}//={};
        return wantarray ? %{ delete $self->{filter} } : delete $self->{filter};
    }

    $self->{filter} = \%args;
    return $self;
}

sub limit {
    my $self = shift;
    my $limit = shift;
    my $offset = shift;

    unless ( $limit ) {
        return delete $self->{limit}, delete $self->{offset};
    }

    $self->{limit} = $limit;
    $self->{offset} = $offset;

    return $self;
}

sub _sort {
    my $self = shift;
    my $dir = shift;
    my @args = @_;

    unless ( @args ) {
        return delete $self->{sort};
    }

    my @sort = @{ $self->{sort} || [] };
    for ( @args ) {
        push @sort, $_ => $dir;
    }

    $self->{sort} = \@sort;
    return $self;
}

sub sort  { shift->_sort('asc', @_ ) };
sub rsort { shift->_sort('desc', @_ ) };

sub reload {
    my $self = shift;
    $self->{res} = {};
    return $self->get( @_ );
}

sub get {
    my $self = shift;
    my %args = @_;

    my $res = $self->{res};
    unless ( %{ $res || {} } ) {
        $res = $self->SUPER::get( %args );
    }
    return undef unless $res;

    $self->res( $res );

    return wantarray ? %{ $self->{res} } : $self->{res};
}

# Method for templates. It always gets scalar
sub pairs { scalar shift->get }

sub items {
    my $self = shift;
    my %args = (
        where => {},
        admin => 0,
        get_smart_args( @_ ),
    );

    $args{where} = {
        %{$args{where}},
        %{$self->query_for_filtering( $self->filter )},
    };

    my @limit = $self->limit();
    $args{limit} //= $limit[0];
    $args{offset} //= $limit[1];

    $args{order} = $self->_sort;

    my @ret = $args{admin} ? $self->_list( %args ) : $self->list( %args );

    my @list;
    for ( @ret ) {
        push @list, $self->new_obj( $_ );
    }

    # always return ref for templates (wantarray is not suitable for templates)
    return \@list;
}

sub first_item {
    my $data = shift;

    return $data->[0] if ref $data eq 'ARRAY';
    return undef;
}

sub lock {
    my $self = shift;
    my %args = (
        timeout => 0,
        @_,
    );

    return 1 unless $self->table;

    my $res;

    until ( $res = $self->SUPER::get( extra => 'FOR UPDATE SKIP LOCKED' )) {
        last unless $args{timeout};
        sleep 1;
        $args{timeout}--;
    }

    if ( $res ) {
        $self->res( $res );
        return 1;
    }
    return 0;
}

sub set_json {
    my $self = shift;
    my $key = shift;
    my $new_data = shift;

    if ( $self->structure->{ $key }->{type} eq 'json' ) {
        my $cur_data = $self->get->{ $key } || {};
        my %args = (
            $key => hash_merge( $cur_data, $new_data ),
        );
        return $self->_add_or_set('set', %args );
    }

    return undef;
}

sub set_settings {
    my $self = shift;
    my $new_data = shift;

    return $self->set_json('settings', $new_data );
}

# Пробуем получить уже загруженные данные
# Проверяем статус операции и обновляем res
sub _add_or_set {
    my $self = shift;
    my $method = shift;
    my %args = @_;

    if ( $self->can('validate_attributes') ) {
        unless ( $self->validate_attributes( $method, %args ) ) {
            logger->warning('validate attribute error:', $method, \%args );
            return undef;
        }
    }

    if ( $method eq 'add' ) {
        if ( my $defaults = get_service('config')->data_by_name('defaults')->{ lc $self->kind } ) {
            %args = %{ hash_merge( $defaults, \%args ) };
        }
    }

    # Преобразуем значения в JSON
    my %super_args = %args;
    for my $key ( keys %args ) {
        next if $key eq 'where';
        my $new_value = $args{ $key };
        if ( ref $new_value eq 'HASH' || ref $new_value eq 'ARRAY' ) {
            $super_args{ $key } = encode_json( $args{ $key } );
        }
    }

    my $ret = $method eq 'add' ? $self->SUPER::add( %super_args ) : $self->SUPER::set( %super_args );

    if ( defined $ret && %{ $self->res } ) {
        for ( keys %args ) {
            $self->{res}->{ $_ } = $args{ $_ } if exists $self->{res}->{ $_ };
        }
    }
    return $ret;
}

sub create {
    my $self = shift;
    my %args = (
        get_smart_args( @_ ),
    );

    my $id = $self->add( %args );
    return undef unless $id;

    return $self->id( $id );
}

sub api_set {
    my $self = shift;
    my %args = @_;

    if ( $self->api('set', %args ) ) {
        return scalar $self->get();
    }

    return ();
}

sub api_add {
    my $self = shift;
    my %args = @_;

    if ( $self->structure ) {
        my $report = get_service('report');
        for my $f ( keys %{ $self->structure } ) {
            if ( $self->structure->{ $f }->{required} ) {
                unless ( exists $args{ $f } ) {
                    $report->add_error( sprintf("Field required: %s", $f) );
                    return ();
                }
            }
        }
    }
    return $self->api('add', %args );
}

sub api {
    my $self = shift;
    my $method = shift;
    my %args = @_;

    %args = $self->api_safe_args( %args ) unless $args{admin};

    return $self->$method( %args );
}

sub api_safe_args {
    my $self = shift;
    my %args = @_;

    return %args unless $self->can('structure');
    my %struct = %{ $self->structure };

    for my $key ( keys %args ) {
        unless ( exists $struct{ $key} && $struct{ $key }->{'allow_update_by_user'} ) {
            delete $args{ $key };
            next;
        }

        if ( $struct{ $key }->{'hide_for_user'} ) {
            delete $args{ $key };
            next;
        }
    }

    return %args;
}

sub add { shift->_add_or_set( 'add', get_smart_args( @_ ) ) }
sub set { shift->_add_or_set( 'set', get_smart_args( @_ ) ) }

sub kind {
    my $self = shift;

    my $kind = ref $self;
    $kind =~s/.*:://g;
    return $kind;
}

sub make_event {
    my $self = shift;
    my $event_name = shift;
    my %args = (
        get_smart_args( @_ ),
    );

    my $event = $self->srv('Events');

    if ( $self->can('events') ) {
        %args = %{ hash_merge(
            $self->events->{ $event_name } || {},
            \%args,
        );
    }}

    if ( $args{event} && $args{event}->{method} ) {
        $args{event}->{name} ||= uc $event_name;
        $args{event}->{kind} ||= $self->kind;
        $event->make( %args );
    }

    my @commands = $event->get_events( name => $event_name );
    for ( @commands ) {
        $event->make(
            event => $_,
            $args{settings} ? ( settings => $args{settings } ) : (),
        );
    }
}

sub list_by_settings {
    my $self = shift;
    my %args = (
        @_,
    );

    $args{ "settings.$_" } = delete $args{ $_ } for keys %args;

    return $self->list(
        where => \%args,
        order => [ $self->get_table_key => 'ASC' ],
    );
}

sub logger {
    my $self = shift;

    if ( $self ) {
        return $self->srv('logger');
    }

    state $log ||= get_service('logger');
    return $log;
}

sub report {
    my $self = shift;

    if ( $self ) {
        return $self->srv('report');
    }

    state $report ||= get_service('report');
    return $report;
}

sub cache {
    my $self = shift;
    state $cache ||= get_service('Core::System::Cache');
    return $cache;
}

sub delete_all {
    my $self = shift;

    return $self->SUPER::_delete(
        where => {
            user_id => $self->user_id,
        },
    );
}

sub srv {
    my $self = shift;
    my $service_name = shift;
    my %args = @_;

    return get_service( $service_name, %args, user_id => $self->user_id );
}

sub get_smart_args {
    my @args = @_;

    if ( ref $args[0] eq 'HASH' ) {
        @args = %{ $args[0] };
    }
    return @args;
}

sub cloud_headers {
    my $self = shift;

    return {
        SHM_INFO_CNT => $self->user->active_count,
        SHM_INFO_VER => get_service('config')->id( '_shm' )->get_data->{'version'},
    }
}

sub set_user_fail_attempt {
    my $self = shift;
    my $method = shift;
    my $expire = shift || 600;
    my $ips = shift || $ENV{TRUSTED_IPS};

    my $user_ip = get_user_ip() || return undef;

    if (my $exclude_ips = $ips) {
        my @ip_ranges = map { s/^\s+|\s+$//gr } split /,/, $exclude_ips;
        return 0 if is_ip_allowed($user_ip, \@ip_ranges);
    }

    my $cache = $self->cache || return undef;
    my $tag = lc sprintf("%s-%s-%s", ref $self, $method, $user_ip);

    return $cache->increment( $tag, $expire );
}

sub arch {
    my $self = shift;

    state $arch ||= `uname -m`;
    chomp $arch;
    return $arch;
}

1;
