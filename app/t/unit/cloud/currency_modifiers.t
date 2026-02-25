#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Data::Dumper;
use v5.14;
use utf8;

$ENV{SHM_TEST} = 1;

# Тестовые данные валют с модификаторами
my $test_currencies = {
    'USD' => {
        'name' => 'US Dollar',
        'value' => 75.50,
        'symbol' => '$'
    },
    'EUR' => {
        'name' => 'Euro',
        'value' => 85.25,
        'symbol' => '€',
        'addition_type' => 'numeric',
        'addition_value' => 5.0  # Прибавляем 5 к базовому курсу
    },
    'GBP' => {
        'name' => 'British Pound',
        'value' => 95.75,
        'symbol' => '£',
        'addition_type' => 'percent',
        'addition_value' => 10  # Прибавляем 10% к базовому курсу
    },
    'CNY' => {
        'name' => 'Chinese Yuan',
        'value' => 11.20,
        'symbol' => '¥',
        'addition_type' => 'fixed',
        'addition_value' => 12.50  # Используем фиксированное значение вместо базового курса
    },
    'RUB' => {
        'name' => 'Russian Ruble',
        'value' => 1.00,
        'symbol' => '₽'
    }
};

use_ok('Core::Cloud::Currency');

# Создаем объект Currency
my $currency = Core::Cloud::Currency->new();

# Мокаем метод currencies
{
    no warnings 'redefine';
    *Core::Cloud::Currency::currencies = sub {
        my $self = shift;
        return $test_currencies;
    };
}

subtest 'get_value method with modifiers' => sub {
    # Тест базового курса без модификаторов
    my $usd_value = $currency->get_value('USD');
    is($usd_value, 75.50, 'USD without modifiers returns base value');

    # Тест numeric модификатора (value + addition_value)
    my $eur_value = $currency->get_value('EUR');
    is($eur_value, 90.25, 'EUR with numeric modifier: 85.25 + 5.0 = 90.25');

    # Тест percent модификатора (value + value * percent / 100)
    my $gbp_value = $currency->get_value('GBP');
    is($gbp_value, 105.325, 'GBP with percent modifier: 95.75 + 95.75 * 10% = 105.325');

    # Тест fixed модификатора (использует addition_value вместо value)
    my $cny_value = $currency->get_value('CNY');
    is($cny_value, 12.50, 'CNY with fixed modifier uses addition_value: 12.50');

    # Тест RUB (базовая валюта)
    my $rub_value = $currency->get_value('RUB');
    is($rub_value, 1, 'RUB always returns 1');
};

subtest 'from method with modifiers (convert from foreign currency to base)' => sub {
    # USD без модификаторов: 100 * 75.50 = 7550.00
    my $result_usd = $currency->from('USD', 100);
    is($result_usd, '7550.00', 'from USD: 100 USD = 7550.00 RUB (no modifier)');

    # EUR с numeric модификатором: 100 * (85.25 + 5.0) = 100 * 90.25 = 9025.00
    my $result_eur = $currency->from('EUR', 100);
    is($result_eur, '9025.00', 'from EUR: 100 EUR = 9025.00 RUB (numeric modifier)');

    # GBP с percent модификатором: 100 * (95.75 + 95.75 * 10%) = 100 * 105.325 = 10532.50
    my $result_gbp = $currency->from('GBP', 100);
    is($result_gbp, '10532.50', 'from GBP: 100 GBP = 10532.50 RUB (percent modifier)');

    # CNY с fixed модификатором: 100 * 12.50 = 1250.00
    my $result_cny = $currency->from('CNY', 100);
    is($result_cny, '1250.00', 'from CNY: 100 CNY = 1250.00 RUB (fixed modifier)');
};

subtest 'to method with modifiers (convert from base currency to foreign)' => sub {
    # USD без модификаторов: 7550 / 75.50 = 100.00
    my $result_usd = $currency->to('USD', 7550);
    is($result_usd, '100.00', 'to USD: 7550 RUB = 100.00 USD (no modifier)');

    # EUR с numeric модификатором: 9025 / 90.25 = 100.00
    my $result_eur = $currency->to('EUR', 9025);
    is($result_eur, '100.00', 'to EUR: 9025 RUB = 100.00 EUR (numeric modifier)');

    # GBP с percent модификатором: 10532.50 / 105.325 = 100.00
    my $result_gbp = $currency->to('GBP', 10532.50);
    is($result_gbp, '100.00', 'to GBP: 10532.50 RUB = 100.00 GBP (percent modifier)');

    # CNY с fixed модификатором: 1250 / 12.50 = 100.00
    my $result_cny = $currency->to('CNY', 1250);
    is($result_cny, '100.00', 'to CNY: 1250 RUB = 100.00 CNY (fixed modifier)');
};

subtest 'edge cases for modifiers' => sub {
    # Создаем тестовые валюты с экстремальными значениями
    my $edge_currencies = {
        'TEST1' => {
            'name' => 'Test Currency 1',
            'value' => 100.0,
            'addition_type' => 'numeric',
            'addition_value' => -50.0  # Отрицательное значение
        },
        'TEST2' => {
            'name' => 'Test Currency 2',
            'value' => 100.0,
            'addition_type' => 'percent',
            'addition_value' => -25  # Отрицательный процент
        },
        'TEST3' => {
            'name' => 'Test Currency 3',
            'value' => 100.0,
            'addition_type' => 'fixed',
            'addition_value' => 0  # Нулевое фиксированное значение
        },
        'TEST4' => {
            'name' => 'Test Currency 4',
            'value' => 100.0,
            'addition_type' => 'unknown',  # Неизвестный тип
            'addition_value' => 50
        }
    };

    # Временно заменяем мок currencies
    no warnings 'redefine';
    local *Core::Cloud::Currency::currencies = sub {
        return $edge_currencies;
    };

    my $test_currency = Core::Cloud::Currency->new();

    # Тест отрицательного numeric модификатора
    my $test1_value = $test_currency->get_value('TEST1');
    is($test1_value, 50.0, 'Negative numeric modifier: 100 - 50 = 50');

    # Тест отрицательного percent модификатора
    my $test2_value = $test_currency->get_value('TEST2');
    is($test2_value, 75.0, 'Negative percent modifier: 100 - 25% = 75');

    # Тест нулевого fixed модификатора
    my $test3_value = $test_currency->get_value('TEST3');
    is($test3_value, 0, 'Zero fixed modifier returns 0');

    # Тест неизвестного типа модификатора
    my $test4_value = $test_currency->get_value('TEST4');
    is($test4_value, 100.0, 'Unknown modifier type returns base value');
};

subtest 'modifier validation' => sub {
    # Валюта только с addition_type, без addition_value
    my $incomplete_currencies = {
        'INCOMPLETE1' => {
            'value' => 50.0,
            'addition_type' => 'numeric'
            # addition_value отсутствует
        },
        'INCOMPLETE2' => {
            'value' => 50.0,
            'addition_value' => 10.0
            # addition_type отсутствует
        }
    };

    no warnings 'redefine';
    local *Core::Cloud::Currency::currencies = sub {
        return $incomplete_currencies;
    };

    my $test_currency = Core::Cloud::Currency->new();

    # Если отсутствует addition_value, должно возвращаться базовое значение
    my $incomplete1_value = $test_currency->get_value('INCOMPLETE1');
    is($incomplete1_value, 50.0, 'Missing addition_value returns base value');

    # Если отсутствует addition_type, должно возвращаться базовое значение
    my $incomplete2_value = $test_currency->get_value('INCOMPLETE2');
    is($incomplete2_value, 50.0, 'Missing addition_type returns base value');
};

subtest 'round-trip conversion with modifiers' => sub {
    # Проверяем точность конвертации туда и обратно с модификаторами
    my $original_amount = 1000;

    for my $curr ('EUR', 'GBP', 'CNY') {
        my $converted = $currency->from($curr, $original_amount);
        my $back_converted = $currency->to($curr, $converted);

        # Проверяем с небольшой погрешностью из-за округления
        my $diff = abs($back_converted - $original_amount);
        ok($diff < 0.01, "Round-trip conversion for $curr with modifier (diff: $diff)");
    }
};

done_testing();