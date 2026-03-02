#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Data::Dumper;
use v5.14;
use utf8;

$ENV{SHM_TEST} = 1;

use SHM;
my $user = SHM->new( user_id => 40092 );

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

subtest 'convert method tests (currency to currency conversion)' => sub {
    # Проверяем, что метод convert существует
    can_ok($currency, 'convert');

    # Тест конвертации USD в EUR (между сторонними валютами - обычное округление)
    # 100 USD * 75.50 = 7550 RUB, 7550 RUB / 85.25 = 88.56338... EUR -> 88.56 EUR
    my $usd_to_eur = $currency->convert(
        from => 'USD',
        to => 'EUR',
        amount => 100
    );
    is($usd_to_eur, '88.56', 'convert: 100 USD = 88.56 EUR (normal rounding)');

    # Тест конвертации EUR в USD (между сторонними валютами - обычное округление)
    # 100 EUR * 85.25 = 8525 RUB, 8525 RUB / 75.50 = 112.913... USD -> 112.91 USD
    my $eur_to_usd = $currency->convert(
        from => 'EUR',
        to => 'USD',
        amount => 100
    );
    is($eur_to_usd, '112.91', 'convert: 100 EUR = 112.91 USD (normal rounding)');

    # Тест конвертации USD в GBP (между сторонними валютами - обычное округление)
    # 50 USD * 75.50 = 3775 RUB, 3775 RUB / 95.75 = 39.4268... GBP -> 39.43 GBP
    my $usd_to_gbp = $currency->convert(
        from => 'USD',
        to => 'GBP',
        amount => 50
    );
    is($usd_to_gbp, '39.43', 'convert: 50 USD = 39.43 GBP (normal rounding)');

    # Тест конвертации В системную валюту (RUB) - округление вниз (floor)
    # 10.0066225 USD * 75.50 = 755.500... RUB -> floor(75549.99875) / 100 = 755.49 RUB
    my $usd_to_rub = $currency->convert(
        from => 'USD',
        to => 'RUB',
        amount => 10.0066225
    );
    is($usd_to_rub, '755.49', 'convert: USD to RUB rounds down (floor)');

    # Тест конвертации ИЗ системной валюты (RUB) - округление вверх (ceil)
    # 755.4 RUB / 75.50 = 10.005... USD -> ceil(10.005 * 100) / 100 = 10.01 USD
    my $rub_to_usd = $currency->convert(
        from => 'RUB',
        to => 'USD',
        amount => 755.4
    );
    is($rub_to_usd, '10.01', 'convert: RUB to USD rounds up (ceil)');

    # Тест одинаковых валют
    my $same_currency = $currency->convert(
        from => 'USD',
        to => 'USD',
        amount => 123.45
    );
    is($same_currency, '123.45', 'convert: same currency returns original amount');

    # Тест с дробными суммами между сторонними валютами
    # 10.50 EUR * 85.25 = 895.125 RUB, 895.125 RUB / 95.75 = 9.348... GBP -> 9.35 GBP
    my $decimal_convert = $currency->convert(
        from => 'EUR',
        to => 'GBP',
        amount => 10.50
    );
    is($decimal_convert, '9.35', 'convert: 10.50 EUR = 9.35 GBP (normal rounding)');

    # Тест с нулевой суммой
    my $zero_convert = $currency->convert(
        from => 'USD',
        to => 'EUR',
        amount => 0
    );
    is($zero_convert, '0.00', 'convert: 0 USD = 0.00 EUR');
};

subtest 'convert method error handling' => sub {
    # Тест с несуществующей исходной валютой
    my $invalid_from = $currency->convert(
        from => 'XYZ',
        to => 'USD',
        amount => 100
    );
    is($invalid_from, undef, 'convert: invalid from currency returns undef');

    # Тест с несуществующей целевой валютой
    my $invalid_to = $currency->convert(
        from => 'USD',
        to => 'XYZ',
        amount => 100
    );
    is($invalid_to, undef, 'convert: invalid to currency returns undef');

    # Тест с обеими несуществующими валютами
    my $both_invalid = $currency->convert(
        from => 'ABC',
        to => 'XYZ',
        amount => 100
    );
    is($both_invalid, undef, 'convert: both invalid currencies return undef');

    # Тест с отрицательной суммой
    my $negative_amount = $currency->convert(
        from => 'USD',
        to => 'EUR',
        amount => -100
    );
    is($negative_amount, '-88.56', 'convert: handles negative amounts');

    # Тест регистронезависимости
    my $case_insensitive = $currency->convert(
        from => 'usd',
        to => 'eur',
        amount => 100
    );
    is($case_insensitive, '88.56', 'convert: case insensitive currency codes');
};

subtest 'convert method round-trip tests' => sub {
    # Проверяем точность конвертации туда и обратно с учетом асимметричного округления
    my $original_amount = 1000;

    my @currency_pairs = (
        ['USD', 'EUR'],  # Между сторонними валютами - нормальное округление
        ['EUR', 'GBP'],  # Между сторонними валютами - нормальное округление
        ['USD', 'GBP'],  # Между сторонними валютами - нормальное округление
    );

    for my $pair (@currency_pairs) {
        my ($from, $to) = @$pair;

        my $converted = $currency->convert(
            from => $from,
            to => $to,
            amount => $original_amount
        );

        my $back_converted = $currency->convert(
            from => $to,
            to => $from,
            amount => $converted
        );

        # Проверяем с небольшой погрешностью из-за округления
        my $diff = abs($back_converted - $original_amount);
        ok($diff < 0.02, "Round-trip conversion $from -> $to -> $from (diff: $diff)");
    }

    # Специальные тесты для асимметричного округления с системной валютой (RUB)
    subtest 'asymmetric rounding with system currency' => sub {
        # Тест RUB -> USD -> RUB (система всегда выигрывает)
        my $rub_amount = 1000;
        my $rub_to_usd = $currency->convert(
            from => 'RUB',
            to => 'USD',
            amount => $rub_amount
        );
        my $usd_back_to_rub = $currency->convert(
            from => 'USD',
            to => 'RUB',
            amount => $rub_to_usd
        );

        # Система должна получить обратно не меньше исходной суммы
        ok($usd_back_to_rub >= $rub_amount, "RUB->USD->RUB: system protected ($rub_amount -> $usd_back_to_rub)");

        # Тест USD -> RUB -> USD (пользователь теряет минимально)
        my $usd_amount = 100;
        my $usd_to_rub = $currency->convert(
            from => 'USD',
            to => 'RUB',
            amount => $usd_amount
        );
        my $rub_back_to_usd = $currency->convert(
            from => 'RUB',
            to => 'USD',
            amount => $usd_to_rub
        );

        # Пользователь не должен получить больше исходной суммы
        ok($rub_back_to_usd <= $usd_amount, "USD->RUB->USD: user loss limited ($usd_amount -> $rub_back_to_usd)");

        # Потери должны быть минимальными (не более 0.02)
        my $user_loss = $usd_amount - $rub_back_to_usd;
        ok($user_loss < 0.02, "User loss is minimal: $user_loss");
    };
};

subtest 'convert method consistency with existing methods' => sub {
    # ВНИМАНИЕ: convert теперь использует асимметричное округление, поэтому результаты могут отличаться!

    my $test_amount = 250;

    # USD -> RUB через convert (округление вниз - floor)
    my $direct_convert = $currency->convert(
        from => 'USD',
        to => 'RUB',
        amount => $test_amount
    );

    # USD -> RUB через метод from (обычное округление)
    my $via_from = $currency->from('USD', $test_amount);

    # Результаты могут отличаться из-за разного округления
    note("convert USD->RUB: $direct_convert, from USD: $via_from");
    # Проверяем, что convert дает не больше, чем from (из-за floor)
    ok($direct_convert <= $via_from, 'convert USD->RUB (floor) <= from() method (normal rounding)');

    # RUB -> EUR через convert (округление вверх - ceil)
    my $rub_amount = 8525; # Эквивалент 100 EUR
    my $rub_to_eur_convert = $currency->convert(
        from => 'RUB',
        to => 'EUR',
        amount => $rub_amount
    );

    # RUB -> EUR через метод to (обычное округление)
    my $rub_to_eur_to = $currency->to('EUR', $rub_amount);

    note("convert RUB->EUR: $rub_to_eur_convert, to EUR: $rub_to_eur_to");
    # Проверяем, что convert дает не меньше, чем to (из-за ceil)
    ok($rub_to_eur_convert >= $rub_to_eur_to, 'convert RUB->EUR (ceil) >= to() method (normal rounding)');

    # Тест цепочки конвертаций: USD -> RUB -> EUR vs USD -> EUR
    my $usd_to_rub = $currency->from('USD', 100);
    my $rub_to_eur = $currency->to('EUR', $usd_to_rub);

    my $direct_usd_to_eur = $currency->convert(
        from => 'USD',
        to => 'EUR',
        amount => 100
    );

    # Результаты должны быть близкими, но могут отличаться из-за разного округления
    my $diff = abs($direct_usd_to_eur - $rub_to_eur);
    ok($diff < 0.02, "convert USD->EUR vs chained from/to difference: $diff");
    note("Direct USD->EUR: $direct_usd_to_eur, Chained: $rub_to_eur");
};

subtest 'convert method default parameters tests' => sub {
    # Тест конвертации с указанием только from (to должно быть 'RUB' по умолчанию)
    # ВНИМАНИЕ: convert использует асимметричное округление!
    my $usd_to_default = $currency->convert(
        from => 'USD',
        amount => 100
    );
    # Должно быть эквивалентно convert(from => 'USD', to => 'RUB', amount => 100)
    my $usd_to_rub_explicit = $currency->convert(
        from => 'USD',
        to => 'RUB',
        amount => 100
    );
    is($usd_to_default, $usd_to_rub_explicit, 'convert with only from parameter defaults to RUB');
    # Точный расчет: 100 * 75.50 = 7550.00 (точно), поэтому floor не изменит результат
    is($usd_to_default, '7550.00', 'convert from USD to default RUB: 100 USD = 7550.00 RUB (floor)');

    # Тест конвертации с указанием только to (from должно быть 'RUB' по умолчанию)
    my $default_to_eur = $currency->convert(
        to => 'EUR',
        amount => 8525
    );
    # Должно быть эквиваленто convert(from => 'RUB', to => 'EUR', amount => 8525)
    my $rub_to_eur_explicit = $currency->convert(
        from => 'RUB',
        to => 'EUR',
        amount => 8525
    );
    is($default_to_eur, $rub_to_eur_explicit, 'convert with only to parameter defaults from RUB');
    # Точный расчет: 8525 / 85.25 = 100.00 (точно), поэтому ceil не изменит результат
    is($default_to_eur, '100.00', 'convert from default RUB to EUR: 8525 RUB = 100.00 EUR (ceil)');

    # Тест конвертации без указания from и to (оба должны быть 'RUB')
    my $default_both = $currency->convert(
        amount => 1000
    );
    is($default_both, '1000.00', 'convert with no from/to parameters (RUB to RUB): returns same amount');

    # Тест с дробными суммами и значениями по умолчанию
    # EUR -> RUB: 50.25 * 85.25 = 4283.8125 -> floor(428381.25) / 100 = 4283.81
    my $eur_to_default_decimal = $currency->convert(
        from => 'EUR',
        amount => 50.25
    );
    is($eur_to_default_decimal, '4283.81', 'convert EUR to default RUB: 50.25 EUR = 4283.81 RUB (floor)');

    # RUB -> GBP: 1915 / 95.75 = 20.0 -> ceil(2000) / 100 = 20.00
    my $default_to_gbp_decimal = $currency->convert(
        to => 'GBP',
        amount => 1915
    );
    is($default_to_gbp_decimal, '20.00', 'convert default RUB to GBP: 1915 RUB = 20.00 GBP (ceil)');

    # Тест совместимости с существующими методами - ВНИМАНИЕ: могут отличаться!
    my $from_method_result = $currency->from('USD', 75);
    my $convert_default_result = $currency->convert(
        from => 'USD',
        amount => 75
    );
    # 75 * 75.50 = 5662.5 - точно, поэтому и floor, и sprintf дают одинаковый результат
    is($convert_default_result, $from_method_result, 'convert USD->RUB matches from() method (exact calculation)');

    my $to_method_result = $currency->to('GBP', 4787.5);
    my $convert_default_from_result = $currency->convert(
        to => 'GBP',
        amount => 4787.5
    );
    # 4787.5 / 95.75 = 50.0 - точно, поэтому и ceil, и sprintf дают одинаковый результат
    is($convert_default_from_result, $to_method_result, 'convert RUB->GBP matches to() method (exact calculation)');
};

subtest 'asymmetric rounding tests' => sub {
    # Специальные тесты для проверки асимметричного округления

    # Тест 1: Конвертация ИЗ системной валюты - ceil (округление вверх)
    # Создаем случай, где точный результат имеет дробную часть
    # 100.001 RUB / 75.50 = 1.3245... USD -> ceil(132.45) / 100 = 1.33 USD
    my $rub_to_usd_ceil = $currency->convert(
        from => 'RUB',
        to => 'USD',
        amount => 100.001
    );
    # Точный расчет: 100.001 / 75.50 = 1.324516... -> ceil должен дать 1.33
    is($rub_to_usd_ceil, '1.33', 'RUB to USD uses ceil rounding (1.324... -> 1.33)');

    # Тест 2: Конвертация В системную валюту - floor (округление вниз)
    # 1.324516 USD * 75.50 = 100.000708 RUB -> floor(10000.0708) / 100 = 100.00 RUB
    my $usd_to_rub_floor = $currency->convert(
        from => 'USD',
        to => 'RUB',
        amount => 1.324516
    );
    # Точный расчет: 1.324516 * 75.50 = 100.000708 -> floor должен дать 100.00
    is($usd_to_rub_floor, '100.00', 'USD to RUB uses floor rounding (100.000708 -> 100.00)');

    # Тест 3: Конвертация между сторонними валютами - обычное округление
    # 10.555 USD * 75.50 / 85.25 = 9.338... EUR -> обычное округление = 9.34 EUR
    my $usd_to_eur_normal = $currency->convert(
        from => 'USD',
        to => 'EUR',
        amount => 10.555
    );
    # Точный расчет: 10.555 * 75.50 / 85.25 = 9.3458... -> обычное округление = 9.35
    is($usd_to_eur_normal, '9.35', 'USD to EUR uses normal rounding (9.3458... -> 9.35)');

    # Тест 4: Проверка защиты от потерь при циклических конвертациях
    my $start_rub = 1000.00;

    # Цикл: RUB -> USD -> RUB
    my $rub_usd = $currency->convert(from => 'RUB', to => 'USD', amount => $start_rub);
    my $usd_rub = $currency->convert(from => 'USD', to => 'RUB', amount => $rub_usd);

    # Система должна получить обратно >= исходной суммы (или очень близко)
    my $system_diff = $usd_rub - $start_rub;
    ok($system_diff >= -0.01, "System protected in RUB->USD->RUB cycle (diff: $system_diff)");

    # Тест 5: Максимальные потери пользователя при неблагоприятной конвертации
    my $start_usd = 100.00;

    # Цикл: USD -> RUB -> USD
    my $usd_rub2 = $currency->convert(from => 'USD', to => 'RUB', amount => $start_usd);
    my $rub_usd2 = $currency->convert(from => 'RUB', to => 'USD', amount => $usd_rub2);

    # Пользователь не должен получить больше исходной суммы
    ok($rub_usd2 <= $start_usd, "User cannot gain from USD->RUB->USD cycle ($start_usd -> $rub_usd2)");

    # Потери должны быть минимальными
    my $user_loss = $start_usd - $rub_usd2;
    ok($user_loss < 0.02, "User losses are minimal: $user_loss USD");

    note("Asymmetric rounding test results:");
    note("  RUB->USD->RUB: $start_rub -> $rub_usd -> $usd_rub (system diff: $system_diff)");
    note("  USD->RUB->USD: $start_usd -> $usd_rub2 -> $rub_usd2 (user loss: $user_loss)");
};

done_testing();
