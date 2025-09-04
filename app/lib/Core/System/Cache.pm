package Core::System::Cache;

use v5.14;
use parent qw/Core::Base/;
use Redis;

use constant {
    REDIS_HOST => 'redis',
    REDIS_PORT => 6379,
};

sub init {
    my $self = shift;
    my %args = (
        @_,
    );

    if ( gethostbyname( REDIS_HOST ) ) {
        $self->{redis} = Redis->new( server => sprintf("%s:%d", REDIS_HOST, REDIS_PORT) );
    }
    return $self;
}

sub redis {
    my $self = shift;
    return $self->{redis};
}

sub set {
    my $self = shift;
    my $key = shift;
    my $value = shift;
    my $expire = shift || 3600; # 1h

    return undef unless $self->redis;
    return undef unless $key;

    return $self->redis->setex( $key, $expire, $value );
}

sub increment {
    my $self = shift;
    my $key = shift;
    my $expire = shift || 3600; # 1h

    return undef unless $self->redis;
    return undef unless $key;

    my $ret = $self->redis->incr( $key );
    $self->redis->expire( $key, $expire );
    return $ret;
}

sub get {
    my $self = shift;
    my $name = shift;
    return undef unless $self->redis;

    return $self->redis->get( $name );
}

1;