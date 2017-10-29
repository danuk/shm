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
        task => undef,
        @_,
    );

    my $us = get_service('us', _id => $args{task}->{user_service_id});

    my @domains;
    for ( $us->domains ) {
        push @domains, $_->{punycode} || $_->{domain};
    }

    my $object = $us->data_for_transport;

    #www create $account $domain_name,$alias $p_params{max_quota} $directory $p_params{group} $tariff_settings{inet_lock}
    my $cmd = join(' ',
        'www',
        $args{task}->{event},
        $args{task}->{user_service_id},
        "$domains[0],www.$domains[0]",
        $object->{settings}->{max_quota},
        $domains[0],
    );

    return SUCCESS, {
        payload => {
            object => $object,
            domains => \@domains,
        },
        cmd => $cmd,
    };
}

# Сюда приходит ответ от транспорта
sub transport_responce_data {
    my $self = shift;

    return SUCCESS;
}

1;
