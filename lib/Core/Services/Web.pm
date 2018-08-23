package Core::Services::Web;

use v5.14;
use parent 'Core::Base';
use Core::Base;

# Имя сервиса в менеджере сервисов.
# Используем один и тот-же экземпляр для сервиса (имя сервиса не содержит идентификатор)
sub _id { return 'Services::Web' };

# Готовим данные для транспорта
sub data_for_transport {
    my $self = shift;
    my %args = (
        user_service_id => undef,
        @_,
    );

    my $us = get_service('us', _id => $args{user_service_id});

    my @domains;
    for ( scalar $us->domains->get ) {
        push @domains, $_->{punycode} || $_->{domain};
    }

    my $object = $us->data_for_transport;

    return SUCCESS, {
        object => $object,
        domains => \@domains,
    };
}

# Сюда приходит ответ от транспорта
sub transport_responce_data {
    my $self = shift;

    return SUCCESS;
}

1;
