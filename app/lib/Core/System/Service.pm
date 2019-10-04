package Core::System::Service;
use strict;

use base qw( Core::System::Object );

use Core::System::ServiceManager qw($SERVICE_MANAGER);

=pod

=module Core::System::Service

=head1 Название

Core::System::Service - базовый класс для сервисов

=head1 Функции

=cut


#-------------------------------------------------------------------------------
=pod

=head2 new

Конструктор сервиса. На вход принимает hash параметров и все их помещает в себя.
Обязательный параметр - id, служит идентификатором сервиса.

=cut

sub new {
    my $proto = shift;
    my %args = (
        id    => undef,
        @_,
    );
    my $class = ref($proto) || $proto;

    return bless(\%args, $class);
}

=pod

=head2 get_id

=cut

#__PACKAGE__->GENERATE_GETTERS( qw(
#    id
#));

#-------------------------------------------------------------------------------
=pod

=head2 register

Регистрирует сервис в менеджере сервисов.

=cut

sub register {
    my $self = shift;
    my $id = shift;
    return $SERVICE_MANAGER->register_service( $self, $id, @_ );
}

=pod

=head2 unregister

Разрегистрирует сервис в менеджере сервисов.

=cut

sub unregister {
    return $SERVICE_MANAGER->unregister_service(shift);
}
#-------------------------------------------------------------------------------


1;
