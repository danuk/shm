package Core::System::Logger;
use v5.14;
use utf8;

=pod

=module MakeIdea::FW::System::Logger

=head1 Название

Класс для записи сообщений в лог. Имеет несколько уровней логгирования:

=item TRACE

=item DEBUG

=item INFO

=item WARNING

=item ERROR

=item FATAL

И соответственно им имеется набор методов для записи сообщений в лог. Уровни
приведены в порядке увеличения важности. Соответственно, при выставлении уровня,
в лог пишутся сообщения этой важности и выше.

=head1 Функции

=cut

use base qw( Core::System::Service );

use Data::Dumper;

use Core::System::ServiceManager qw(get_service $data);

#-------------------------------------------------------------------------------
my $LEVEL_TRACE     = 0;
my $LEVEL_DEBUG     = 1;
my $LEVEL_INFO      = 2;
my $LEVEL_WARNING   = 3;
my $LEVEL_ERROR     = 4;
my $LEVEL_FATAL     = 5;

my %LEVELS = (
    TRACE   => $LEVEL_TRACE,
    DEBUG   => $LEVEL_DEBUG,
    INFO    => $LEVEL_INFO,
    WARNING => $LEVEL_WARNING,
    WARN    => $LEVEL_WARNING,
    ERROR   => $LEVEL_ERROR,
    FATAL   => $LEVEL_FATAL,
);
#-------------------------------------------------------------------------------


# class MakeIdea::FW::System::Logger -------------------------------------------
=pod

=head2 new

Конструктор. На вход может принимать уровень логгирования и имя проекта, при их
отсутствии - берет из конфигурации системы. При отсутствии в конфигурации системы
информации об уровне логгировния, использует флаг debug. В случае, если он
включен - уровень TRACE, если выключен - ERROR.

=cut

sub new {
    my $proto = shift;
    my %args = (
        id      => 'logger',
        level   => undef,
        stacktrace_from => undef,
        @_
    );

    my $class = ref($proto) || $proto;

    my $self = bless(Core::System::Service->new(%args), $class);

    my $level = $ENV{DEBUG} ? 'DEBUG' : 'ERROR';
    $self->set_level_to( $level );

    #$self->add_stacktrace_from_level( $args{stacktrace_from} || $config->{log_stacktrace_from} || 'ERROR' );

    return $self;
}

=head2 set_level_to

Принимает название уроввня и изменятет текущий уровень логирования.

=cut

sub set_level_to {
    my $self = shift;
    my $level = shift;

    $self->{level} = $LEVELS{ uc $level // '' };
    unless ( $self->{level} ) {
        $self->{level} = $LEVEL_WARNING;
        $self->warning("Unknown log level '" . ($level // '(undef)') . "'");
    }

    return $self;
}

sub add_stacktrace_from_level {
    my $self = shift;
    my $level = shift;

    $self->{stacktrace_from} = $LEVELS{ uc $level // '' };
    unless ( $self->{stacktrace_from} ) {
        $self->{stacktrace_from} = $LEVEL_ERROR;
        $self->warning("Unknown log level '" . ($level // '(undef)') . "'");
    }

    return $self;
}

# messages constructors --------------------------------------------------------
=pod

=head2 make_message

Генерирует сообщение для лога

=cut

sub make_message {
    my $self = shift;
    my %args = (
        msg => '',
        tag => '',
        stacktrace => 1,
        @_,
    );

    my ($package, $filename, $line) = caller(1);

    my $res = "$args{tag}"
            . " [" . scalar(localtime) .  "]"
            . " pid: $$"
            . " message: {{ $args{msg} }}"
            . "\n";

    if ($args{stacktrace}) {
        my $level = 2;
        while ( my ($package, $filename, $line, $subroutine) = caller($level++) ) {
            $res .= "\t$subroutine at $filename line $line\n";
        }
    }

    if ($self->{extended_info}) {
        $res .= "\tEXTENDED INFO:\n"
              . "\t$self->{extended_info}\n";
    }

    return $res;
}


# printing methods -------------------------------------------------------------
=pod

=head2 trace

=head2 dump

На вход принимет объект (ссылку) или список объектов. Выводит в лог dump этих объектов

=head2 debug

=head2 info

=head2 warning

=head2 error

=head2 fatal

=cut

sub my_warn {
    my $self = shift;
    print STDERR join($, // '', @_, "\n");
    return;
}

sub trace   { shift->_log( 'TRACE', @_ ) }
sub dump    { shift->_log( 'DEBUG', Data::Dumper->new( [@_] )->Indent(1)->Quotekeys(0)->Sortkeys(1)->Dump() ) }
sub debug   { shift->_log( 'DEBUG', @_ ) }
sub info    { shift->_log( 'INFO', @_ ) }
sub warning { shift->_log( 'WARNING', @_ ) }
sub error   { shift->_log( 'ERROR', @_ ); exit 1 }
sub fatal   { shift->_log( 'FATAL', @_ ) }

sub level_permitted {
    my $self = shift;
    my $level = shift;
    return $self->{level} <= $LEVELS{ uc $level };
}

sub _log {
    my $self = shift;
    my $level = shift;
    my $msg = join '', @_;

    my $level_number = $LEVELS{ uc $level } // die "Wrong log level '$level'";
    if ( $self->level_permitted( $level ) ) {
        $self->my_warn( $self->make_message(
            msg => $msg, tag => $level,
            stacktrace => $level_number >= $self->{stacktrace_from}? 1 : 0,
        ) );
    }
    return $self;
}

sub force {
    my $self = shift;
    $self->my_warn(
        $self->make_message(msg => join('', @_), tag => 'FORCE', stacktrace => 0));
}

sub profiler {
    my ( $self, @data ) = @_;
    if ( @data && get_service('config')->get->{config}->{log_profiler} ) {
        $self->my_warn( join( '=#=', 'admin_stat', @data ) ."\n");
    }
}

1;
