package Core::Services::Dns;

use v5.14;
use parent 'Core::Base';
use Core::Base;

sub _id { return 'Services::Dns' };

sub data_for_transport {
    my $self = shift;
    my %args = (
        user_service_id => undef,
        @_,
    );

    my ( $domain_service ) = get_service('domain')->list_services(
        user_service_id => $args{user_service_id},
    );

    unless ( $domain_service ) {
        return FAIL, { error => 'domain not exists for user_service: ' . $args{user_service_id} };
    }

    my $domain = get_service('domain', _id => $domain_service->{domain_id} );

    my @dns = $domain->dns_records;

    return SUCCESS, {
        payload => {
            domain => $domain->real_domain,
            records => \@dns,
        },
        cmd => 'dns create',
    };
}

# Сюда приходит ответ от транспорта
sub transport_responce_data {
    my $self = shift;

    return SUCCESS;
}

1;
