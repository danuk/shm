# Proxy wrapper around a real Redis connection.
# All method calls are eval-protected internally.
# Automatically tries to reconnect after RECONNECT_INTERVAL seconds.
package Core::System::Cache::SafeRedis;

use v5.14;
use Redis;

use constant RECONNECT_INTERVAL => 10;

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {
        host     => $args{host},
        port     => $args{port},
        _redis   => undef,
        last_try => 0,
    }, $class;
    $self->_try_connect();
    return $self;
}

sub _try_connect {
    my $self = shift;
    $self->{last_try} = time();
    $self->{_redis} = eval {
        Redis->new(
            server    => sprintf( "%s:%d", $self->{host}, $self->{port} ),
            reconnect => 0,
        );
    };
}

sub is_connected {
    my $self = shift;
    return !!$self->{_redis};
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    ( my $method = $AUTOLOAD ) =~ s/.*:://;

    # Attempt reconnect if disconnected and interval has passed
    if ( !$self->{_redis} && time() - $self->{last_try} >= RECONNECT_INTERVAL ) {
        $self->_try_connect();
    }

    return wantarray ? () : undef unless $self->{_redis};

    my @result = eval { $self->{_redis}->$method( @_ ) };
    if ( $@ ) {
        $self->{_redis} = undef; # mark as disconnected
        return wantarray ? () : undef;
    }
    return wantarray ? @result : $result[0];
}

sub DESTROY {}


package Core::System::Cache;

use v5.14;
use parent qw/Core::Base/;
use Core::Utils qw(
    encode_json
    decode_json
);

use constant {
    REDIS_HOST => 'redis',
    REDIS_PORT => 6379,
};

sub init {
    my $self = shift;

    $self->{redis} = Core::System::Cache::SafeRedis->new(
        host => REDIS_HOST,
        port => REDIS_PORT,
    );

    return $self;
}

sub _id {}; # всегда один экземляр для всех

sub redis {
    my $self = shift;
    return $self->{redis};
}

sub set {
    my $self = shift;
    my $key = shift;
    my $value = shift;
    my $expire = shift;
    $expire //= 3600; # 1h по умолчанию

    return undef unless $key;

    if ( ref $value ) {
        $value = encode_json( $value );
    }

    return $self->redis->set( $key, $value ) if $expire == 0;
    return $self->redis->setex( $key, $expire, $value );
}

sub set_json { shift->set( @_ ) };

sub increment {
    my $self = shift;
    my $key = shift;
    my $expire = shift || 3600; # 1h

    return undef unless $key;

    my $ret = $self->redis->incr( $key );
    return undef unless defined $ret;
    $self->redis->expire( $key, $expire );
    return $ret;
}

sub get {
    my $self = shift;
    my $name = shift || return undef;

    return $self->redis->get( $name );
}

sub get_json { decode_json shift->get( shift ) };

sub delete {
    my $self = shift;
    my $name = shift || return undef;

    my $data = $self->get( $name );
    $self->redis->del( $name ) if $data;
    return $data;
}

sub delete_json { decode_json shift->delete( shift ) };

1;