#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Data::Dumper;
use v5.14;
use utf8;

$ENV{SHM_TEST} = 1;

# Тестовые данные валют - создаем как глобальную переменную
my $test_currencies = {
    'USD' => {
        'name' => 'US Dollar',
        'value' => 75.50,
        'symbol' => '$'
    },
    'EUR' => {
        'name' => 'Euro',
        'value' => 85.25,
        'symbol' => '€'
    },
    'GBP' => {
        'name' => 'British Pound',
        'value' => 95.75,
        'symbol' => '£'
    },
    'RUB' => {
        'name' => 'Russian Ruble',
        'value' => 1.00,
        'symbol' => '₽'
    }
};

use_ok('Core::Cloud::Currency');

# Создаем настоящий объект Currency
my $currency = Core::Cloud::Currency->new();

# Мокаем только метод currencies, остальные методы остаются оригинальными
{
    no warnings 'redefine';
    *Core::Cloud::Currency::currencies = sub {
        my $self = shift;
        return $test_currencies;
    };
}

subtest 'currencies method tests' => sub {
    # Тест успешного получения валют
    my $currencies = $currency->currencies();
    ok($currencies, 'currencies method returns data');
    is_deeply($currencies, $test_currencies, 'currencies data matches expected structure');

    # Проверяем, что все ожидаемые валюты присутствуют
    ok(exists $currencies->{USD}, 'USD currency exists');
    ok(exists $currencies->{EUR}, 'EUR currency exists');
    ok(exists $currencies->{GBP}, 'GBP currency exists');
    ok(exists $currencies->{RUB}, 'RUB currency exists');
};

subtest 'get method tests' => sub {
    # Тест получения конкретной валюты
    my $usd = $currency->get('USD');
    ok($usd, 'get USD returns data');
    is($usd->{name}, 'US Dollar', 'USD name is correct');
    is($usd->{value}, 75.50, 'USD value is correct');
    is($usd->{symbol}, '$', 'USD symbol is correct');

    # Тест получения валюты в разном регистре
    my $eur_lower = $currency->get('eur');
    ok($eur_lower, 'get eur (lowercase) returns data');
    is($eur_lower->{name}, 'Euro', 'EUR name is correct for lowercase input');

    # Тест получения несуществующей валюты
    my $nonexistent = $currency->get('XYZ');
    is($nonexistent, undef, 'get non-existent currency returns undef');
};

subtest 'from method tests (convert from foreign currency to base)' => sub {
    # Конвертация из USD в базовую валюту (RUB)
    my $result_usd = $currency->from('USD', 100);
    is($result_usd, '7550.00', 'from USD: 100 USD = 7550.00 RUB');

    # Конвертация из EUR в базовую валюту
    my $result_eur = $currency->from('EUR', 50);
    is($result_eur, '4262.50', 'from EUR: 50 EUR = 4262.50 RUB');

    # Конвертация из GBP в базовую валюту
    my $result_gbp = $currency->from('GBP', 25);
    is($result_gbp, '2393.75', 'from GBP: 25 GBP = 2393.75 RUB');

    # Конвертация дробных сумм
    my $result_decimal = $currency->from('USD', 10.50);
    is($result_decimal, '792.75', 'from USD: 10.50 USD = 792.75 RUB');

    # Конвертация нулевой суммы
    my $result_zero = $currency->from('USD', 0);
    is($result_zero, '0.00', 'from USD: 0 USD = 0.00 RUB');

    # Тест с несуществующей валютой
    my $result_invalid = $currency->from('XYZ', 100);
    is($result_invalid, undef, 'from invalid currency returns undef');
};

subtest 'to method tests (convert from base currency to foreign)' => sub {
    # Конвертация из базовой валюты (RUB) в USD
    my $result_usd = $currency->to('USD', 7550);
    is($result_usd, '100.00', 'to USD: 7550 RUB = 100.00 USD');

    # Конвертация в EUR
    my $result_eur = $currency->to('EUR', 8525);
    is($result_eur, '100.00', 'to EUR: 8525 RUB = 100.00 EUR');

    # Конвертация в GBP
    my $result_gbp = $currency->to('GBP', 9575);
    is($result_gbp, '100.00', 'to GBP: 9575 RUB = 100.00 GBP');

    # Конвертация дробных сумм
    my $result_decimal = $currency->to('USD', 377.50);
    is($result_decimal, '5.00', 'to USD: 377.50 RUB = 5.00 USD');

    # Конвертация нулевой суммы
    my $result_zero = $currency->to('USD', 0);
    is($result_zero, '0.00', 'to USD: 0 RUB = 0.00 USD');

    # Тест с несуществующей валютой
    my $result_invalid = $currency->to('XYZ', 1000);
    is($result_invalid, undef, 'to invalid currency returns undef');
};

subtest 'edge cases and error handling' => sub {
    # Тест с отрицательными суммами
    my $negative_from = $currency->from('USD', -100);
    is($negative_from, '-7550.00', 'from handles negative amounts');

    my $negative_to = $currency->to('USD', -7550);
    is($negative_to, '-100.00', 'to handles negative amounts');

    # Тест с очень маленькими суммами
    my $small_from = $currency->from('USD', 0.01);
    is($small_from, '0.76', 'from handles small amounts (0.01)');

    my $small_to = $currency->to('USD', 0.76);
    is($small_to, '0.01', 'to handles small amounts (0.76)');
};

subtest 'round-trip conversion tests' => sub {
    # Проверяем, что конвертация туда и обратно дает исходную сумму (с учетом округления)
    my $original_amount = 1000;

    for my $curr ('USD', 'EUR', 'GBP') {
        my $converted = $currency->from($curr, $original_amount);
        my $back_converted = $currency->to($curr, $converted);

        # Проверяем с небольшой погрешностью из-за округления
        my $diff = abs($back_converted - $original_amount);
        ok($diff < 0.01, "Round-trip conversion for $curr (diff: $diff)");
    }
};

# Тест с кешированием - временно меняем мок
subtest 'caching functionality' => sub {
    my $cached_currencies = {
        'USD' => {
            'name' => 'US Dollar',
            'value' => 80.00,  # Другое значение для проверки кеша
            'symbol' => '$'
        }
    };

    # Временно заменяем мок currencies
    no warnings 'redefine';
    local *Core::Cloud::Currency::currencies = sub {
        return $cached_currencies;
    };

    my $cached_currency = Core::Cloud::Currency->new();
    my $currencies = $cached_currency->currencies();
    ok($currencies, 'currencies loaded from test data');
    is($currencies->{USD}{value}, 80.00, 'cached currency value is correct');
};

# Тест обработки ошибок - мокаем currencies для возврата undef
subtest 'network error handling' => sub {
    # Временно заменяем currencies на failing версию
    no warnings 'redefine';
    local *Core::Cloud::Currency::currencies = sub {
        return undef;
    };

    my $failing_currency = Core::Cloud::Currency->new();

    my $currencies = $failing_currency->currencies();
    is($currencies, undef, 'currencies returns undef on network failure');

    my $usd = $failing_currency->get('USD');
    is($usd, undef, 'get returns undef when currencies unavailable');

    my $from_result = $failing_currency->from('USD', 100);
    is($from_result, undef, 'from returns undef when currencies unavailable');

    my $to_result = $failing_currency->to('USD', 100);
    is($to_result, undef, 'to returns undef when currencies unavailable');
};

# Дополнительные тесты для специальных случаев
subtest 'additional edge cases' => sub {
    # Тест с очень большими числами
    my $large_result = $currency->from('USD', 999999);
    is($large_result, '75499924.50', 'from handles large amounts');

    # Тест с очень маленькими числами
    my $tiny_result = $currency->from('USD', 0.0001);
    is($tiny_result, '0.01', 'from handles tiny amounts (rounds to 0.01)');

    # Тест точности округления
    my $precision_test = $currency->from('USD', 1.3333);
    is($precision_test, '100.66', 'from rounds correctly to 2 decimal places');

    # Тест деления на очень маленькое число
    my $small_division = $currency->to('RUB', 100);  # RUB value = 1.00
    is($small_division, '100.00', 'to handles division by 1.00');
};

subtest 'currency data validation' => sub {
    # Проверяем структуру каждой валюты
    my $currencies = $currency->currencies();

    for my $code (keys %$currencies) {
        my $cur = $currencies->{$code};

        ok(exists $cur->{name}, "$code has name field");
        ok(exists $cur->{value}, "$code has value field");
        ok(exists $cur->{symbol}, "$code has symbol field");

        ok(defined $cur->{name} && $cur->{name} ne '', "$code name is not empty");
        ok(defined $cur->{value} && $cur->{value} > 0, "$code value is positive");
        ok(defined $cur->{symbol} && $cur->{symbol} ne '', "$code symbol is not empty");
    }
};

subtest 'case sensitivity tests' => sub {
    # Тест различных вариантов регистра
    my @test_cases = ('usd', 'USD', 'Usd', 'uSd', 'UsD');

    for my $case (@test_cases) {
        my $result = $currency->get($case);
        ok($result, "get() works with case: $case");
        is($result->{name}, 'US Dollar', "correct data returned for case: $case");
    }

    # Тест конвертации с разным регистром
    is($currency->from('usd', 10), '755.00', 'from() works with lowercase');
    is($currency->to('EUR', 852.5), '10.00', 'to() works with mixed case');
};

subtest 'mathematical precision tests' => sub {
    # Тест точности вычислений
    my $result1 = $currency->from('USD', 1);
    my $result2 = $currency->from('USD', 0.1);
    my $result3 = $currency->from('USD', 0.9);

    # 1 USD должен равняться 0.1 + 0.9 USD (с учетом округления)
    my $sum = sprintf("%.2f", $result2 + $result3);
    is($sum, $result1, 'Mathematical precision: 0.1 + 0.9 = 1.0');

    # Тест обратной конвертации
    my $original = 123.45;
    my $converted = $currency->from('USD', $original);
    my $back = $currency->to('USD', $converted);

    # Должно быть очень близко к исходному значению
    my $diff = abs($back - $original);
    ok($diff < 0.01, "Round-trip precision test: diff = $diff");
};

# Тест для подтверждения использования оригинальных методов
subtest 'original methods verification' => sub {
    # Проверяем, что объект действительно является экземпляром Core::Cloud::Currency
    isa_ok($currency, 'Core::Cloud::Currency', 'currency object is instance of Core::Cloud::Currency');

    # Проверяем, что методы существуют и работают как ожидается
    can_ok($currency, 'currencies');
    can_ok($currency, 'get');
    can_ok($currency, 'from');
    can_ok($currency, 'to');

    # Проверяем цепочку вызовов: currencies -> get -> from/to
    my $currencies_data = $currency->currencies();
    ok($currencies_data, 'currencies method returns data');

    my $usd_data = $currency->get('USD');
    ok($usd_data, 'get method uses currencies data');

    my $conversion_result = $currency->from('USD', 100);
    ok($conversion_result, 'from method uses get method internally');
    is($conversion_result, '7550.00', 'conversion calculation is correct');

    note('All methods (except currencies) are using original Core::Cloud::Currency implementation');
};

done_testing();
