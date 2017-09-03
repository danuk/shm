package Core::Client;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub new {
    my $proto  = shift;
    my $class = ref($proto) || $proto;

    my $args = { id => 'client' };

    my $config = get_service('config')->get->{config};

    $args->{dbh} = Core::Sql::Data::db_connect( map{ $_ => $config->{$_} } qw(db_name db_host db_user db_pass) );
    return undef unless $args->{dbh};

    return bless( $args, $class );
}

sub id {
    my ( $self, $client_id ) = @_;

    unless ( $client_id ) {
        return $self->{id}->{client_id} || confess('Client not loaded');
    }

    my $data = $self->query("SELECT * FROM clients WHERE client_id = ?", $client_id );
    return undef unless $data;

    $self->{id} = $data->[0];

    return $self;
}

sub search_client {
    my $self = shift;
    my %args = (
        agent => undef,
        ip => undef,
        host => undef,
        @_,
    );

    my $res = $self->query("SELECT * FROM clients WHERE (agent= ? ) or
                                        (ip IS NOT NULL and ip= ? ) or
                                        (host IS NOT NULL and host= ? ) LIMIT 1",
        $args{agent}, $args{ip}, $args{host}
    );
    return undef unless $res;

    return $res->[0];
}

sub user_db {
    my $self = shift;
    return map{ $_ => $self->{id}->{$_} } qw(db_name db_host db_user db_pass);
}

sub user {
    my $self = shift;
    return get_service('user', client_id => $self->id, $self->user_db );
}

1;

