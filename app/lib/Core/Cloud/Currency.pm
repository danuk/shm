package Core::Cloud::Currency;

use v5.14;
use parent 'Core::Cloud';
use Core::Base;
use POSIX qw(floor ceil);
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

    # Если в кеше нет данных или они устарели (более 1 часа)
    my $cache_time = $self->cache->get('currencies_timestamp') || 0;
    my $current_time = time();
    my $cache_expired = ($current_time - $cache_time) > 3600; # 1 час

    if ( !$currencies || $cache_expired ) {
        my $response = $self->cloud_request( url => '/service/currencies/list' );

        if ( $response && $response->is_success ) {
            my $new_currencies = decode_json $response->decoded_content();
            if ( $new_currencies ) {
                $currencies = $new_currencies;
                # Сохраняем навсегда, но будем пробовать обновлять каждый час
                $self->cache->set_json('currencies', $currencies, 0);
                $self->cache->set('currencies_timestamp', $current_time, 0);
            } else {
                logger->warning("Can't decode currencies from Cloud, using cached data");
            }
        } else {
            logger->warning("Can't load currencies from Cloud, using cached data");
        }

        # Если обновление не удалось и кеша нет, возвращаем undef
        return undef unless $currencies;
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
        url => '/service/currencies/list',
        content => {
            format => 'json',
            currencies => $args{currencies},
        },
    );
    return undef unless $response && $response->is_success;

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

sub system_currency {
    my $self = shift;

    state $currency //= get_service('config', _id => 'billing')->get_data->{currency} || 'RUB';
    return $currency;
}

sub convert {
    my $self = shift;
    my %args = (
        from => '',
        to => '',
        amount => 0,
        @_,
    );

    my $system_currency = $self->system_currency;
    my $from_currency = uc $args{from} || $system_currency;
    my $to_currency = uc $args{to} || $system_currency;
    my $amount = $args{amount};

    return sprintf("%.2f", $amount) if $from_currency eq $to_currency;

    my $from_value = $self->get_value($from_currency);
    my $to_value = $self->get_value($to_currency);

    return undef unless defined $from_value && defined $to_value;

    my $rub_amount = $amount * $from_value;
    my $converted_amount = $rub_amount / $to_value;

    # Асимметричное округление для защиты от потерь при обратной конвертации
    if ($from_currency eq $system_currency) {
        # Конвертируем ИЗ системной валюты - округляем вверх
        return sprintf("%.2f", ceil($converted_amount * 100) / 100);
    }
    elsif ($to_currency eq $system_currency) {
        # Конвертируем В системную валюту - округляем вниз
        return sprintf("%.2f", floor($converted_amount * 100) / 100);
    }
    else {
        # Конвертация между не-системными валютами - обычное округление
        return sprintf("%.2f", $converted_amount);
    }
}

1;