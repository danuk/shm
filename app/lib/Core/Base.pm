package Core::Base;

use v5.14;
use utf8;
use parent qw( Core::Sql::Data Core::System::Service );
use Core::System::ServiceManager qw( get_service logger );
use Core::Sql::Data;
use Carp qw(confess);
use Data::Dumper;
use Core::Utils qw(
    force_numbers
    hash_merge
    encode_json
    hash_merge
);
$Data::Dumper::Deepcopy = 1;

our @EXPORT = qw(
    get_service
    Dumper
    confess
    logger
);

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    my $self = shift;

    if ( $AUTOLOAD =~ /^.*::(get_)?(\w+)$/ ) {
        my $method = $2;

        unless ( my %res = $self->res ) {
            # load data if not loaded before
            $self->get;
        }

        if ( exists $self->res->{ $method } ) {
            return $self->res->{ $method };
        }
        else {
            logger->warning("Field `$method` not exists in structure.");
            return undef;
        }
    } elsif ( $AUTOLOAD=~/::DESTROY$/ ) {
        # Skip
    } else {
        confess ("Method not exists: " . $AUTOLOAD );
    }
}

sub new {
    my $proto = shift;
    my $args = {
        _id => undef,
        @_,
    };
    my $class = ref($proto) || $proto;
    my $self = bless( $args, $class );

    # Устанавливаем идентификатор автоматически
    if ( defined $args->{_id} && $class->can('structure') ) {
        $args->{ $class->get_table_key } = delete $args->{_id};

        # Выходим если не смогли загрузить данные по идентификатору
        return undef unless $self->get;
    }

    if ( $self->can('init') ) {
        return $self->init( %{ $args } );
    }
    return $self;
}

sub id {
    my $self = shift;
    my $id = shift;

    if ( defined $id ) {
        return get_service( ref $self, _id => $id );
    }

    my $key_field = $self->get_table_key;

    unless ( $self->{ $key_field } || $self->res->{ $key_field } ) {
        logger->warning('identifier not defined for class ' . ref $self);
        return undef;
    }
    return $self->{ $key_field } || $self->res->{ $key_field };
}

sub user_id {
    my $self = shift;
    return exists $self->{user_id} ? $self->{user_id} : get_service('config')->local->{user_id};
}

sub user {
    my $self = shift;
    return get_service('user', _id => $self->user_id );
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

    $self->{res} = $res;

    return wantarray ? %{ $self->{res} } : $self->{res};
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
    $self->reload();
    return $res ? 1 : 0;
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

# Пробуем получить уже загруженные данные
# Проверяем статус операции и обновляем res
sub _add_or_set {
    my $self = shift;
    my $method = shift;
    my %args = @_;

    if ( $self->can('validate_attributes') ) {
        return undef unless $self->validate_attributes( $method, %args );
    }

    # Преобразуем значения в JSON
    my %super_args = %args;
    for my $key ( keys %args ) {
        my $new_value = $args{ $key };
        if ( ref $new_value eq 'HASH' || ref $new_value eq 'ARRAY' ) {
            $super_args{ $key } = encode_json( force_numbers $args{ $key } );
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
        }
    }

    return %args;
}

sub add { return shift->_add_or_set( 'add', @_ ) }
sub set { shift->_add_or_set( 'set', @_ ) }

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
        @_,
    );

    my $event = get_service('Events');

    if ( $self->can('events') ) {
        %args = %{ hash_merge(
            $self->events->{ $event_name } || {},
            \%args,
        );
    }}

    if ( $args{event} ) {
        $args{event}->{kind}||= $self->kind;
        $event->make( %args );
    }

    my @commands = $event->get_events( name => $event_name );
    for ( @commands ) {
        $event->make( event => $_ );
    }
}

sub list_by_settings {
    my $self = shift;
    my %args = (
        @_,
    );

    $args{ "settings->$_" } = delete $args{ $_ } for keys %args;

    return $self->list(
        where => \%args,
        order => [ $self->get_table_key => 'ASC' ],
    );
}

sub logger {
    state $log ||= get_service('logger');
    return $log;
}

1;
