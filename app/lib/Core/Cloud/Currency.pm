package Core::Cloud::Currency;

use v5.14;
use parent 'Core::Cloud';
use Core::Base;
use Core::Utils qw(
    encode_json
    decode_json
);

sub currencies {
    my $self = shift;
    my %args = (
        no_cache => 0,
        @_,
    );

    $self->cache->delete('currencies') if $args{no_cache};
    my $currencies = $self->cache->get_json('currencies');

    unless ( $currencies ) {
        my $response = $self->cloud_request( url => '/service/currencies' );
        return undef unless $response;
        $currencies = $response->json_content();
        unless ( $currencies ) {
            logger->warning("Can't load currencies from Cloud");
            return undef;
        };
        $self->cache->set_json('currencies', $currencies, 86400);
    }

    return $currencies;
}

sub save {
    my $self = shift;
    my %args = (
        currencies => {},
        @_,
    );

    my $response = $self->cloud_request(
        method => 'POST',
        url => '/service/currencies',
        content => {
            format => 'json',
            currencies => $args{currencies},
        },
    );
    return undef unless $response;

    my $currencies = decode_json $response->decoded_content;

    $self->cache->set('currencies', $currencies, 86400);

    return $currencies;
}

sub get {
    my $self = shift;
    my $currency = uc shift;

    my $currencies = $self->currencies;
    return undef unless $currencies;

    return $currencies->{ $currency };
}

sub get_value {
    my $self = shift;
    my $currency = uc shift;

    return 1 if $currency eq 'RUB';
    my $cur = $self->get( $currency );
    return $cur ? $self->_calculate_effective_value($cur) : undef;
}

sub _calculate_effective_value {
    my $self = shift;
    my $cur = shift;

    return undef unless $cur && defined $cur->{value};

    my $base_value = $cur->{value};
    my $addition_type = $cur->{addition_type};
    my $addition_value = $cur->{addition_value};

    return $base_value unless defined $addition_type && defined $addition_value;

    if ($addition_type eq 'fixed') {
        return $addition_value;
    }
    elsif ($addition_type eq 'numeric') {
        return $base_value + $addition_value;
    }
    elsif ($addition_type eq 'percent') {
        my $percent_amount = $base_value * ($addition_value / 100);
        return $base_value + $percent_amount;
    }

    return $base_value;
}

sub from {
    my $self = shift;
    my $currency = shift;
    my $amount = shift;

    my $value = $self->get_value( $currency );
    return undef unless $value;

    my $total = $amount * $value;
    return sprintf( "%.2f", $total );
}

sub to {
    my $self = shift;
    my $currency = shift;
    my $amount = shift;

    my $value = $self->get_value( $currency );
    return undef unless $value;

    my $total = $amount / $value;
    return sprintf( "%.2f", $total );
}

1;