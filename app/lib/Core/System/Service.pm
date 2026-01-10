package Core::System::Service;
use strict;
use Core::System::ServiceManager qw($SERVICE_MANAGER);

sub new {
    my $proto = shift;
    my %args = (
        id    => undef,
        @_,
    );
    my $class = ref($proto) || $proto;

    return bless(\%args, $class);
}

sub register {
    my $self = shift;
    my $id = shift;
    return $SERVICE_MANAGER->register_service( $self, $id, @_ );
}

sub unregister {
    return $SERVICE_MANAGER->unregister_service(shift);
}

1;
