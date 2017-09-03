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

    my $domain = get_service('domain')->get_domain(
        user_service_id => $args{user_service_id},
    );

    unless ( $domain ) {
        return FAIL, { error => 'domain not exists for user_service: ' . $args{user_service_id} };
    }

    my @dns = $domain->dns_records;

    return SUCCESS, {
        domain => $domain->real_domain,
        records => \@dns,
    };
}

# Сюда приходит ответ от транспорта
sub transport_responce_data {
    my $self = shift;

    return SUCCESS;
}

1;
