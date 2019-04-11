package Core::Base;

use v5.14;
use utf8;
use parent qw( Core::Sql::Data Core::System::Service );
use Core::System::ServiceManager qw( get_service logger );
use Core::Sql::Data;
use Carp qw(confess);
use Data::Dumper;
use JSON;
$Data::Dumper::Deepcopy = 1;

our @EXPORT = qw(
    get_service
    Dumper
    confess
    logger
);

sub new {
    my $proto = shift;
    my $args = {
        _id => undef,
        @_,
    };
    my $class = ref($proto) || $proto;
    my $self = bless( $args, $class );

    # Устанавливаем идентификатор автоматически
    if ( $args->{_id} && $class->can('structure') ) {
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
        return $self->new( _id => $id );
    }

    my $key_field = $self->get_table_key;

    unless ( $self->{ $key_field } || $self->res->{ $key_field } ) {
        get_service('logger')->warning('identifier not defined for class ' . ref $self);
        return undef;
    }
    return $self->{ $key_field } || $self->res->{ $key_field };
}

sub dbh {
    my $self = shift;
    return get_service('config')->local->{dbh} || die "Can't connect to db";
}

sub user_id {
    my $self = shift;
    return exists $self->{user_id} ? $self->{user_id} : get_service('config')->local->{user_id};
}

sub res {
    my $self = shift;
    my $res = shift;

    unless ( $res ) {
        $self->{res}//={};
        return wantarray ? %{ $self->{res} } : $self->{res};
    }

    if ( ref $res ne 'HASH' ) {
        get_service('logger')->error("Can't set SCALAR data to resource");
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

    $self->{res} = $res;

    return wantarray ? %{ $self->{res} } : $self->{res};
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
        if ( ref $new_value eq 'HASH' ) {
            $super_args{ $key } = to_json( $args{ $key } );
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

sub add { return shift->_add_or_set( 'add', @_ ) }
sub set { shift->_add_or_set( 'set', @_ ) }

sub kind {
    my $self = shift;

    my $kind = ref $self;
    $kind =~s/.*:://g;
    return lc $kind;
}

sub make_event {
    my $self = shift;
    my $event = shift;
    my %args;

    if ( $self->can('events') ) {
        %args = %{ $self->events->{ $event } || {} };
    }

    unless ( $args{event} ) {
        logger->error('Event not defined');
    }

    $args{event}->{kind}||= $self->kind;

    return get_service('Events')->make( %args );
}

sub list_by_params {
    my $self = shift;
    my %args = (
        @_,
    );

    $args{ "params->$_" } = delete $args{ $_ } for keys %args;

    return $self->list( where => \%args );
}

1;
