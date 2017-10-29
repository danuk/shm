package Core::Base;

use v5.14;
use utf8;
use parent qw( Core::Sql::Data Core::System::Service );
use Core::System::ServiceManager qw( get_service );
use Core::Sql::Data;
use Carp qw(confess);
use Data::Dumper;
$Data::Dumper::Deepcopy = 1;

our @EXPORT = qw(
    get_service
    Dumper
    SUCCESS
    FAIL
    TASK_NEW
    TASK_SUCCESS
    TASK_FAIL
    TASK_DROP
    confess
);

use constant SUCCESS => 1;
use constant FAIL => 0;

use constant TASK_NEW => 0;
use constant TASK_SUCCESS => 1;
use constant TASK_FAIL => 2;
use constant TASK_DROP => 3;

sub new {
    my $proto = shift;
    my $args = {
        _id => undef,
        @_,
    };
    my $class = ref($proto) || $proto;

    # Устанавливаем идентификатор автоматически
    if ( $args->{_id} && $class->can('structure') ) {
        $args->{ $class->get_table_key } = delete $args->{_id};
    }

    my $self = bless( $args, $class );
    $self->init( %{ $args } ) if $self->can('init');

    return $self;
}

sub id {
    my $self = shift;
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

sub add {
    my $self = shift;
    my %args = @_;

    if ( $self->can('validate_attributes') ) {
        return undef unless $self->validate_attributes( %args );
    }

    return $self->SUPER::add( %args );
}

# Пробуем получить уже загруженные данные
# Проверяем статус операции и обновляем res
#sub set {
#
#}

1;
