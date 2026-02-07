package Core::System::Cache;

use v5.14;
use parent qw/Core::Base/;
use Redis;
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
    my %args = (
        @_,
    );

    if ( gethostbyname( REDIS_HOST ) ) {
        $self->{redis} = Redis->new( server => sprintf("%s:%d", REDIS_HOST, REDIS_PORT) );
    }
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

    return undef unless $self->redis;
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

    return undef unless $self->redis;
    return undef unless $key;

    my $ret = $self->redis->incr( $key );
    $self->redis->expire( $key, $expire );
    return $ret;
}

sub get {
    my $self = shift;
    my $name = shift || return undef;
    return undef unless $self->redis;

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