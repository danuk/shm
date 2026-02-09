package Core::System::Logger;
use v5.14;
use utf8;

use base qw( Core::System::Service );

use Data::Dumper;
use Core::System::ServiceManager qw(get_service $data);
use Core::Utils qw(
    encode_json
    blessed
);

$SIG{__DIE__} = sub {
    my $error = shift;

    # 1. Проверяем, является ли ошибка объектом Template::Exception
    if (blessed($error) && $error->isa('Template::Exception')) {
        my $type = $error->type;
        # 2. Если это STOP или RETURN, просто выходим из обработчика
        return if $type eq 'stop' || $type eq 'return';
    }

    # Во всех остальных случаях — логируем
    get_service('logger')->error($error);
};

my $LEVEL_TRACE     = 0;
my $LEVEL_DEBUG     = 1;
my $LEVEL_DUMP      = 1;
my $LEVEL_INFO      = 2;
my $LEVEL_WARNING   = 3;
my $LEVEL_ERROR     = 4;
my $LEVEL_FATAL     = 5;

my %LEVELS = (
    TRACE   => $LEVEL_TRACE,
    DEBUG   => $LEVEL_DEBUG,
    DUMP    => $LEVEL_DUMP,
    INFO    => $LEVEL_INFO,
    WARNING => $LEVEL_WARNING,
    WARN    => $LEVEL_WARNING,
    ERROR   => $LEVEL_ERROR,
    FATAL   => $LEVEL_FATAL,
);

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

    my $level = $ENV{DEBUG} ? ( exists $LEVELS{ $ENV{DEBUG} } ? $ENV{DEBUG} : 'DEBUG' ) : 'ERROR';
    $self->set_level_to( $level );
    #$self->add_stacktrace_from_level( $args{stacktrace_from} || $config->{log_stacktrace_from} || 'ERROR' );
    return $self;
}

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

sub make_message {
    my $self = shift;
    my %args = (
        msg => [],
        tag => 'DEBUG',
        stacktrace => 1,
        time => 1,
        color => 1,
        pid => 1,
        @_,
    );

    my @msg = @{ $args{msg} };
    for ( @msg ) {
        if ( ref $_ eq 'HASH' || ref $_ eq 'ARRAY' ) {
            $_ = encode_json( $_ );
        } elsif ( blessed $_ ) {
            $_ = Data::Dumper->new( [ $_ ] )->Indent(0)->Quotekeys(0)->Sortkeys(1)->Terse(1)->Dump();
        }
    }
    my $msg = join(' ', @msg );

    my ($package, $filename, $line) = caller(1);

    my %tag_color = (
        INFO => "\033[0;34m$args{tag}\033[0m",
        ERROR => "\033[0;31m$args{tag}\033[0m",
        FATAL => "\033[0;31m$args{tag}\033[0m",
        WARNING => "\033[0;33m$args{tag}\033[0m",
        DEBUG => "\033[0;32m$args{tag}\033[0m",
        DUMP => "\033[0;33m$args{tag}\033[0m",
    );

    my @ret;
    push @ret, $args{color} ? "$tag_color{ $args{tag} }\t" : "$args{tag}\t" if $args{tag};
    push @ret, "[" . scalar(localtime) .  "]" if $args{time};
    push @ret, "pid: $$" if $args{pid};
    push @ret, "message: {{ $msg }}";

    my $res = join ' ', @ret;

    if ($args{stacktrace}) {
        $res .= "\n";
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

sub my_warn {
    my $self = shift;
    print STDERR join($, // '', @_, "\n");
    return;
}

sub write_log_file {
    my $msg = join($, // '', @_, "\n");

    use Core::System::ServiceManager;
    my $config = Core::System::ServiceManager::is_registered( 'config' );
    return unless $config;

    if ( $config->file->{config}{log} && $ENV{SHM_LOG_TO_FILE} ) {
        my $log = $config->file->{config}{log}->{path} . '/' . $config->file->{config}{log}->{file};
        my $fd;
        open ( $fd, ">> $log" ) or die $!;
        binmode( $fd, ':utf8');
        print $fd $msg;
        close $fd;
    }
    return 1;
}

sub trace   { shift->_log( 'TRACE', @_ ) }
sub dump    { shift->_log( 'DUMP', Data::Dumper->new( [@_] )->Indent(1)->Quotekeys(0)->Sortkeys(1)->Terse(1)->Dump() ) }
sub debug   { shift->_log( 'DEBUG', @_ ) }
sub info    { shift->_log( 'INFO', @_ ) }
sub warning { shift->_log( 'WARNING', @_ ) }
sub error   { shift->_log( 'ERROR', @_ ) }
sub fatal   { shift->_log( 'FATAL', @_ ); exit 1 }

sub level_permitted {
    my $self = shift;
    my $level = shift;
    return $self->{level} <= $LEVELS{ uc $level };
}

sub _log {
    my $self = shift;
    my $level = shift;
    my @msg = @_;

    my $level_number = $LEVELS{ uc $level } // die "Wrong log level '$level'";
    if ( $self->level_permitted( $level ) ) {
        $self->my_warn( $self->make_message(
            msg => \@msg, tag => $level,
            stacktrace => $level_number >= $self->{stacktrace_from}? 1 : 0,
        ) );
    }
    # write_log_file(
    #     $self->make_message(
    #         msg => $msg,
    #         tag => $level,
    #         color => 0,
    #     )
    # );
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
