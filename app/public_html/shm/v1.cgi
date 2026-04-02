#!/usr/bin/perl

use v5.14;
use utf8;
use SHM qw(:all);

use Router::Simple;
use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(
    parse_args
    encode_json
    decode_json
    is_email
    switch_user
    blessed
    print_header
    print_json
    get_user_ip
    qrencode
);

use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;

state $routes //= {
'/healthcheck' => {
    GET => {
        params => {},
        controller => 'Test',
        method => 'healthcheck',
        skip_check_auth => 1,
    },
},
'/test' => {
    GET => {
        params => {},
        controller => 'Test',
        skip_check_auth => 1,
    },
},
'/test/http/echo' => {
    GET => {
        controller => 'Test',
        method => 'http_echo',
        skip_check_auth => 1,
    },
    PUT => {
        controller => 'Test',
        method => 'http_echo',
        skip_check_auth => 1,
    },
    POST => {
        controller => 'Test',
        method => 'http_echo',
        skip_check_auth => 1,
    },
    DELETE => {
        controller => 'Test',
        method => 'http_echo',
        skip_check_auth => 1,
    },
},
'/company' => {
    GET => {
        params => {},
        controller => 'Config',
        method => 'api_data_by_company',
        skip_check_auth => 1,
    },
},
'/user/captcha' => {
    swagger => { tags => 'Капча' },
    GET => {
        params => {},
        controller      => 'User',
        method          => 'gen_captcha',
        skip_check_auth => 1,
        swagger => { summary => 'Получение капчи' },
    },
},
'/user' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        controller => 'User',
        method => 'list_for_api', # hide COMMON_LIST_PARAMS
        swagger => { summary => 'Получение пользователя' },
        params => {},
    },
    PUT => {
        controller => 'User',
        method => 'reg_api_safe',
        skip_check_auth => 1,
        params => {
            login => { type => 'string', required => 1, min_length => 1, max_length => 64 },
            login_type => { type => 'string', required => 0, enum => ['login','email'] },
            password => { type => 'string', required => 1, min_length => 10, max_length => 128 },
            full_name => { type => 'string', required => 0, min_length => 1, max_length => 64 },
            phone => { type => 'string', required => 0, min_length => 1, max_length => 16 },
            partner_id => { type => 'integer', min => 2 },
        },
        swagger => { summary => 'Регистрация пользователя' },
    },
},
'/user/referrals' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        params => {},
        controller => 'User',
        method => 'api_referrals',
            swagger => { summary => 'Получение количества рефералов' },
    },
},
'/user/auth' => {
    swagger => { tags => 'Пользователи' },
    POST => {
        controller => 'User',
        method => 'auth_api_safe',
        skip_check_auth => 1,
        params => {
            login    => { type => 'string', required => 1, min_length => 1, max_length => 64 },
            password => { type => 'string', required => 1, min_length => 1, max_length => 128 },
            otp_token => { type => 'string', required => 0, min_length => 1, max_length => 128 },
        },
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Авторизация (получение `session_id`)',
            responses => {
                '200' => {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                properties => {
                                    id => {
                                        type => 'string'
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
},
'/user/password-auth' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        params => {},
        controller => 'User',
        method => 'api_password_auth_status',
        swagger => { summary => 'Статус входа по паролю' },
    },
    POST => {
        params => {},
        controller => 'User',
        method => 'api_enable_password_auth',
        swagger => { summary => 'Включить вход по паролю' },
    },
    DELETE => {
        params => {},
        controller => 'User',
        method => 'api_disable_password_auth',
        swagger => { summary => 'Отключить вход по паролю' },
    },
},
'/user/otp' => {
    swagger => { tags => 'OTP' },
    GET => {
        params => {},
        controller => 'User::OTP',
        method => 'api_status',
        swagger => { summary => 'Статус OTP' },
    },
    POST => {
        params => {
            token => { type => 'string', required => 1, min_length => 1, max_length => 16 },
        },
        controller => 'User::OTP',
        method => 'api_verify',
        swagger => { summary => 'Проверка OTP' },
    },
    PUT => {
        params => {
            token => { type => 'string', required => 1, min_length => 1, max_length => 16 },
        },
        controller => 'User::OTP',
        method => 'api_enable',
        swagger => { summary => 'Включение OTP' },
    },
    DELETE => {
        params => {
            token => { type => 'string', required => 1, min_length => 1, max_length => 16 },
        },
        controller => 'User::OTP',
        method => 'api_disable',
        swagger => { summary => 'Отключение OTP' },
    },
},
'/user/otp/setup' => {
    swagger => { tags => 'OTP' },
    POST => {
        params => {},
        controller => 'User::OTP',
        method => 'api_setup',
        swagger => {
            summary => 'Настройка OTP',
            responses => {
                '200' => {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                properties => {
                                    qr_url => {
                                        type => 'string'
                                    },
                                    secret => {
                                        type => 'string'
                                    },
                                    backup_codes => {
                                        type => 'array',
                                        items => {
                                            type => 'number'
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
},
'/user/passkey/register' => {
    swagger => { tags => 'Passkey Регистрация' },
    GET => {
        params => {},
        controller => 'User::Passkey',
        method => 'api_register_options',
        swagger => { summary => 'Получить параметры регистрации Passkey' },
    },
    POST => {
        params => {
            credential_id => { type => 'string', required => 1, min_length => 1, max_length => 512 },
            response      => { type => 'string', required => 1, min_length => 1, max_length => 8192 },
        },
        controller => 'User::Passkey',
        method => 'api_register_complete',
        swagger => { summary => 'Завершить регистрацию Passkey' },
    },
},
'/user/passkey' => {
    swagger => { tags => 'Passkey Настройки' },
    GET => {
        params => {},
        controller => 'User::Passkey',
        method => 'api_list',
        swagger => { summary => 'Список зарегистрированных Passkey' },
    },
    POST => {
        params => {
            credential_id => { type => 'string', required => 1, min_length => 1, max_length => 512 },
            name          => { type => 'string', required => 1, min_length => 1, max_length => 128 },
        },
        controller => 'User::Passkey',
        method => 'api_rename',
        swagger => { summary => 'Переименовать зарегистрированный Passkey по идентификатору' },
    },
    DELETE => {
        params => {
            credential_id => { type => 'string', required => 1, min_length => 1, max_length => 512 },
        },
        controller => 'User::Passkey',
        method => 'api_delete',
        swagger => { summary => 'Удалить зарегистрированный Passkey по идентификатору' },
    },
},
'/user/auth/passkey' => {
    swagger => { tags => 'Passkey Аутентификация' },
    GET => {
        params => {},
        controller => 'User::Passkey',
        method => 'api_auth_options_public',
        skip_check_auth => 1,
        swagger => { summary => 'Получить параметры публичной аутентификации Passkey' },
    },
    POST => {
        params => {
            credential_id => { type => 'string', required => 1, min_length => 1, max_length => 512 },
            response      => { type => 'string', required => 1, min_length => 1, max_length => 8192 },
        },
        controller => 'User::Passkey',
        method => 'api_auth_public',
        skip_check_auth => 1,
        swagger => { summary => 'Аутентификация пользователя с помощью Passkey' },
    },
},
'/user/passwd' => {
    swagger => { tags => 'Пользователи' },
    POST => {
        swagger => { summary => 'Сменить пароль пользователя' },
        controller => 'User',
        method => 'passwd',
        params => {
            password => { type => 'string', required => 1, min_length => 6, max_length => 128 },
        },
    },
},
'/user/passwd/reset' => {
    swagger => { tags => 'Пользователи' },
    POST => {
        params => {
            login => { type => 'string', min_length => 1, max_length => 64 },
            email => { type => 'email', max_length => 254 },
        },
        controller => 'User',
        method => 'passwd_reset_request',
        skip_check_auth => 1,
        swagger => { summary => 'Запрос на сброс пароля пользователя' },
    },
},
'/user/passwd/reset/verify' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        controller => 'User',
        method => 'passwd_reset_verify',
        skip_check_auth => 1,
        params => {
            token => { type => 'string', required => 1, min_length => 8, max_length => 256 },
        },
        swagger => { summary => 'Проверка токена сброса пароля пользователя перед сменой пароля' },
    },
    POST => {
        controller => 'User',
        method => 'passwd_reset_verify',
        skip_check_auth => 1,
        params => {
            password => { type => 'string', required => 1, min_length => 6, max_length => 128 },
            token    => { type => 'string', required => 1, min_length => 8, max_length => 256 },
        },
        swagger => { summary => 'Сменить пароль пользователя по токену сброса' },
    },
},
'/user/accounts' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        controller => 'User::Logins',
        swagger    => { summary => 'Список аккаунтов пользователя' },
    },
    DELETE => {
        params => {
            login => { type => "string", min_length => 1, max_length => 128 },
        },
        controller => 'User::Logins',
    },
},
'/user/email' => {
    swagger => { tags => 'Пользователи' },
    PUT => {
        controller => 'User',
        method => 'set_email',
        params => {
            email => { type => 'email', required => 1, max_length => 254 },
        },
        swagger => { summary => 'Привязать email пользователя' },
    },
    GET => {
        params => {},
        controller => 'User',
        method => 'get_email',
        swagger => { summary => 'Получить email пользователя' },
    },
    POST => {
        params => {
            email => { type => 'email', required => 1, max_length => 254 },
            code  => { type => 'string', min_length => 1, max_length => 16 },
        },
        controller => 'User',
        method => 'verify_email',
        swagger => { summary => 'Верифицировать email пользователя' },
    },
    DELETE => {
        params => {
            email => { type => 'email', required => 1, max_length => 254 },
        },
        controller => 'User',
        method => 'delete_email',
        swagger => { summary => 'Удалить email пользователя' },
    },
},
'/user/service' => {
    swagger => { tags => 'Услуги пользователей' },
    GET => {
        controller => 'USObject',
        params => {
            user_service_id => { type => 'integer', min => 1 },
        },
        swagger => { summary => 'Список услуг пользователя' },
    },
    DELETE => {
        controller => 'USObject',
        params => {
            user_service_id => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Удалить услугу пользователя' },
    },
},
'/user/service/stop' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'block_force',
        params => {
            user_service_id => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Остановить услугу пользователя' },
    },
},
'/user/service/change' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'change',
        params => {
            user_service_id => { type => 'integer', required => 1, min => 1 },
            service_id      => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Сменить тариф' },
    },
},
'/user/withdraw' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        controller => 'Withdraw',
        swagger => { summary => 'Списания средств' },
    },
},
'/user/autopayment' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        params => {},
        controller => 'User',
        method => 'list_autopayments',
        swagger => { summary => 'Список автоплатежей пользователя' },
    },
    DELETE => {
        params => {},
        controller => 'User',
        method => 'delete_autopayment',
        args => {
            format => 'json',
        },
        swagger => { summary => 'Удалить автоплатежи пользователя' },
    },
},
'/user/pay' => {
    swagger => { tags => 'Платежи' },
    GET => {
        controller => 'Pay',
        swagger => { summary => 'Список платежей пользователя' },
    },
},
'/user/pay/forecast' => {
    swagger => { tags => 'Платежи' },
    GET => {
        params => {
            days           => { type => 'integer', min => 1, max => 90 },
            consider_today => { type => 'boolean' },
            blocked        => { type => 'boolean' },
        },
        controller => 'Pay',
        method => 'forecast',
        swagger => { summary => 'Прогноз оплаты' },
    },
},
'/user/pay/paysystems' => {
    swagger => { tags => 'Платежи' },
    GET => {
        params => {
            amount    => { type => 'number', min => 0 },
            paysystem => { type => 'string', max_length => 64 },
            pp        => { type => 'boolean' },
        },
        controller => 'Pay',
        method => 'api_paysystems',
        swagger => { summary => 'Платежные системы' },
    },
},
'/service/order' => {
    swagger => { tags => 'Услуги' },
    GET => {
        params => {},
        controller => 'Service',
        method => 'api_price_list',
        swagger => { summary => 'Список услуг для заказа' },
    },
    PUT => {
        controller => 'USObject',
        method => 'create_for_api_safe',
        params => {
            service_id => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Регистрация услуги' },
    },
},
'/service' => {
    swagger => { tags => 'Услуги' },
    GET => {
        swagger => { summary => 'Информация об услуге' },
        controller => 'Service',
        params => {
            service_id => { type => 'integer', required => 1, min => 1 },
        },
    },
},
'/template/*' => {
    swagger => { tags => 'Шаблоны' },
    splat_to => 'id',
    GET => {
        params => {},
        controller => 'Template',
        method => 'parse_for_api',
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Выполнить шаблон' },
    },
    POST => {
        params => {},
        controller => 'Template',
        method => 'parse_for_api',
        skip_auto_parse_json => 1,
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Выполнить шаблон с аргументами' },
    },
},
'/public/*' => {
    swagger => { tags => 'Шаблоны' },
    splat_to => 'id',
    GET => {
        params => {},
        user_id => 1,
        controller => 'Template',
        method => 'parse_for_public',
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Выполнить публичный шаблон' },
    },
    POST => {
        params => {},
        user_id => 1,
        controller => 'Template',
        method => 'parse_for_public',
        skip_auto_parse_json => 1,
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Выполнить публичный шаблон с аргументами' },
    },
},
# метод для случаев, когда нужно сохранить ещё и settings
'/storage/manage' => {
    swagger => { tags => 'Хранилище' },
    GET => {
        params => {},
        controller => 'Storage',
        swagger => { summary => 'Список данных' },
    },
    PUT => { #TODO
        params => {},
        controller => 'Storage',
        swagger => { summary => 'Создать данные в хранилище' },
    },
    POST => { #TODO
        params => {},
        controller => 'Storage',
        swagger => { summary => 'Изменить данные в хранилище' },
    },
    DELETE => { #TODO
        params => {},
        controller => 'Storage',
        swagger => { summary => 'Удалить данные в хранилище' },
    },
},
'/storage/manage/*' => {
    swagger => { tags => 'Хранилище' },
    splat_to => 'name',
    GET => {
        params => {},
        controller => 'Storage',
        method => 'read',
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Прочитать данные из хранилища' },
    },
    PUT => {
        params => {},
        controller => 'Storage',
        method => 'add',
        skip_auto_parse_json => 1,
        allow_text_plain => 1,
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Создать данные в хранилище' },
    },
    POST => {
        params => {},
        controller => 'Storage',
        method => 'replace',
        skip_auto_parse_json => 1,
        allow_text_plain => 1,
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Изменить данные в хранилище' },
    },
    DELETE => {
        params => {},
        controller => 'Storage',
        method => 'delete',
        swagger => { summary => 'Удалить данные из хранилища' },
    },
},
'/storage/download/*' => {
    swagger => { tags => 'Хранилище' },
    splat_to => 'name',
    GET => {
        params => {},
        controller => 'Storage',
        method => 'download',
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Скачать данные из хранилища' },
    },
},
'/promo' => {
    swagger => { tags => 'Промокоды' },
    GET => {
        params => {},
        controller => 'Promo',
        method => 'api_get',
        swagger => {
            summary => 'Список промокодов пользователя',
            responses => {
                '200' => {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                properties => {
                                    promo_code => {
                                        type => 'string',
                                    },
                                    created => {
                                        type => 'string',
                                        format => 'date-time',
                                    },
                                    expire => {
                                        type => 'string',
                                        format => 'date-time',
                                    },
                                    reusable => {
                                        type => 'integer',
                                        enum => [0, 1],
                                    },
                                    status => {
                                        type => 'integer',
                                        enum => [0, 1],
                                    },
                                    used => {
                                        type => 'integer',
                                        enum => [0, 1],
                                        description => 'Использован ли промокод (только для одноразовых, для reusable всегда 0)',
                                    },
                                    used_date => {
                                        type => 'string',
                                        format => 'date-time',
                                        description => 'Дата использования промокода',
                                    },
                                    used_by => {
                                        type => 'integer',
                                        description => 'ID пользователя, использовавшего промокод',
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
},
'/promo/apply/*' => {
    swagger => { tags => 'Промокоды' },
    splat_to => 'code',
    GET => {
        params => {},
        controller => 'Promo',
        method => 'api_apply',
        args => {
            format => 'json',
        },
        swagger => { summary => 'Применить промокод' },
    },
},
'/admin/system/version' => {
    GET => {
        params => {},
        controller => 'Config',
        method => 'version_info',
        args => {
            format => 'json',
        },
    },
},
'/admin/service' => {
    swagger => { tags => 'Услуги' },
    GET => {
        params => {
            service_id => { type => 'integer', min => 1 },
        },
        controller => 'Service',
        swagger => { summary => 'Получить услугу' },
    },
    PUT => {
        controller => 'Service',
        swagger => { summary => 'Создать услугу' },
    },
    POST => {
        controller => 'Service',
        swagger => { summary => 'Изменить услугу' },
    },
    DELETE => {
        params => {
            service_id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Service',
        swagger => { summary => 'Удалить услугу' },
    },
},
'/admin/service/order' => {
    swagger => { tags => ['Услуги','Услуги пользователей'] },
    GET => {
        params => {},
        controller => 'Service',
        method => 'api_price_list',
        swagger => { summary => 'Список услуг доступных для регистрации' },
    },
    PUT => {
        params => {
            user_id    => { type => 'integer', required => 1, min => 1 },
            service_id => { type => 'integer', required => 1, min => 1 },
            months     => { type => 'number', min => 1 },
            cost       => { type => 'number', min => 0 },
            setting    => { type => 'object' },
        },
        controller => 'USObject',
        method => 'create_for_api',
        swagger => { summary => 'Зарегистрировать услугу клиенту' },
    },
},
'/admin/service/children' => {
    swagger => { tags => 'Услуги' },
    GET => {
        params => {
            service_id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Service',
        method => 'api_subservices_list',
        swagger => { summary => 'Список дочерних услуг' },
    },
    POST => {
        params => {
            service_id => { type => 'integer', required => 1, min => 1 },
            children   => { type => 'object', required => 1 },
        },
        controller => 'Service',
        method => 'children',
        swagger => { summary => 'Изменить список дочерних услуг' },
    },
},
'/admin/service/event' => {
    swagger => { tags => 'События' },
    GET => {
        controller => 'Events',
        swagger => { summary => 'Список событий' },
    },
    PUT => {
        controller => 'Events',
        swagger => { summary => 'Создать событие' },
    },
    POST => {
        controller => 'Events',
        swagger => { summary => 'Изменить событие' },
    },
    DELETE => {
        params => {
            id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Events',
        swagger => { summary => 'Удалить событие' },
    },
},
'/admin/user' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        controller => 'User',
        swagger => { summary => 'Список клиентов' },
    },
    PUT => {
        controller => 'User',
        method => 'reg',
        swagger => { summary => 'Создать клиента' },
    },
    POST => {
        controller => 'User',
        swagger => { summary => 'Изменить клиента' },
    },
    DELETE => {
        controller => 'User',
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
            force => { type => 'boolean' },
        },
        swagger => { summary => 'Удалить клиента' },
    },
},
'/admin/user/search' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        params => {
            text => { type => 'string', min_length => 1, max_length => 128 },
        },
        controller => 'User',
        method => 'api_search_for_admins',
        swagger => { summary => 'Поиск клиентов' },
    },
},
'/admin/user/accounts' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        controller => 'User::Logins',
        swagger    => { summary => 'Список аккаунтов' },
    },
    PUT => {
        controller => 'User::Logins',
        swagger    => { summary => 'Добавить аккаунт' },
    },
    POST => {
        controller => 'User::Logins',
        swagger    => { summary => 'Изменить аккаунт' },
    },
    DELETE => {
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
            login   => { type => 'string', required => 1, min_length => 1, max_length => 128 },
            type    => { type => 'string', required => 1, min_length => 1, max_length => 32 },
        },
        controller => 'User::Logins',
        method     => 'api_delete',
        swagger    => { summary => 'Удалить аккаунт' },
    },
},
'/admin/user/passwd' => {
    swagger => { tags => 'Пользователи' },
    POST => {
        controller => 'User',
        method => 'passwd',
        params => {
            user_id  => { type => 'integer', required => 1, min => 1 },
            password => { type => 'string',  required => 1, min_length => 6, max_length => 128 },
        },
        swagger => { summary => 'Сменить пароль клиенту' },
    },
},
'/admin/user/payment' => {
    swagger => { tags => 'Пользователи' },
    PUT => {
        controller => 'User',
        method => 'payment',
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
            money   => { type => 'number',  required => 1 },
            pay_system_id => { type => 'string' },
            comment => { type => 'object' },
        },
        swagger => { summary => 'Зачислить деньги клиенту' },
    },
},
'/admin/user/profile' => {
    GET => {
        params => {},
        controller => 'Profile',
    },
    PUT => {
        controller => 'Profile',
    },
    POST => {
        controller => 'Profile',
    },
    DELETE => {
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
            id      => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Profile',
    },
},
'/admin/user/pay' => {
    swagger => { tags => 'Платежи' },
    GET => {
        controller => 'Pay',
        swagger => { summary => 'Список платежей клиентов' },
    },
    DELETE => {
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
            id      => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Pay',
        swagger => { summary => 'Удалить платеж клиента' },
    },
},
'/admin/user/bonus' => {
    swagger => { tags => 'Бонусы' },
    GET => {
        controller => 'Bonus',
        swagger => { summary => 'Список бонусов клиентов' },
    },
    PUT => {
        controller => 'Bonus',
        swagger => { summary => 'Создать бонус' },
    },
    POST => {
        controller => 'Bonus',
        swagger => { summary => 'Изменить бонус' },
    },
    DELETE => {
        params => {
            id      => { type => 'integer', required => 1, min => 1 },
            user_id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Bonus',
        swagger => { summary => 'Удалить бонус' },
    },
},
'/admin/user/service' => {
    swagger => { tags => 'Услуги пользователей' },
    GET => {
        params => {
            user_id         => { type => 'integer', min => 1 },
            service_id      => { type => 'integer', min => 1 },
            user_service_id => { type => 'integer', min => 1 },
        },
        controller => 'UserService',
        swagger => { summary => 'Список услуг клиентов' },
    },
    PUT => {
        controller => 'USObject',
    },
    POST => {
        controller => 'USObject',
        swagger => { summary => 'Изменить услугу клиента' },
    },
    DELETE => {
        params => {
            user_id         => { type => 'integer', required => 1, min => 1 },
            user_service_id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'USObject',
        swagger => { summary => 'Удалить услугу клиента' },
    },
},
'/admin/user/service/categories' => {
    swagger => { tags => 'Услуги пользователей' },
    GET => {
        params => {},
        controller => 'Service',
        method => 'categories',
        swagger => { summary => 'Получить список категорий услуг' },
    },
},
'/admin/user/service/withdraw' => {
    swagger => { tags => 'Списания' },
    GET => {
        params => {
            user_id     => { type => 'integer', min => 1 },
            withdraw_id => { type => 'integer', min => 1 },
        },
        controller => 'Withdraw',
        swagger => { summary => 'Получить список списаний клиентов' },
    },
    PUT => {
        controller => 'Withdraw',
        swagger => { summary => 'Создать списание клиенту' },
    },
    POST => {
        controller => 'Withdraw',
        swagger => { summary => 'Изменить списание клиента' },
    },
    DELETE => {
        params => {
            user_id     => { type => 'integer', required => 1, min => 1 },
            withdraw_id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Withdraw',
        swagger => { summary => 'Удалить списание клиента' },
    },
},
'/admin/user/service/status' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'set_status_manual',
        params => {
            user_id         => { type => 'integer', required => 1, min => 1 },
            user_service_id => { type => 'integer', required => 1, min => 1 },
            status          => { type => 'string', required => 1, enum => ['ACTIVE','BLOCK'] },
        },
        swagger => { summary => 'Сменить статус услуги клиента' },
    },
},
'/admin/user/service/stop' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'block_force',
        params => {
            user_id         => { type => 'integer', required => 1, min => 1 },
            user_service_id => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Остановить услугу клиента' },
    },
},
'/admin/user/service/activate' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'activate_force',
        params => {
            user_id         => { type => 'integer', required => 1, min => 1 },
            user_service_id => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Возобновить услугу клиента' },
    },
},
'/admin/user/service/touch' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'touch_api',
        params => {
            user_id         => { type => 'integer', required => 1, min => 1 },
            user_service_id => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Обработать услугу' },
    },
},
'/admin/user/service/change' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'change',
        params => {
            user_id         => { type => 'integer', required => 1, min => 1 },
            user_service_id => { type => 'integer', required => 1, min => 1 },
            service_id      => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Сменить тариф услуги клиента' },
    },
},
'/admin/user/service/spool' => {
    swagger => { tags => ['Услуги пользователей','Задачи'] },
    GET => {
        controller => 'USObject',
        method => 'api_spool_commands',
        params => {
            user_id         => { type => 'integer', required => 1, min => 1 },
            user_service_id => { type => 'integer', required => 1, min => 1 },
        },
        swagger => { summary => 'Получить список текущих задач для услуги клиента' },
    },
},
'/admin/user/session' => {
    swagger => { tags => 'Пользователи' },
    PUT => {
        controller => 'User',
        method => 'gen_session',
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
        },
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Сгенерировать session_id для клиента',
                responses => {
                '200' => {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                properties => {
                                    id => {
                                        type => 'string'
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
},
'/admin/server' => {
    swagger => { tags => 'Сервера' },
    GET => {
        params => {
            server_id  => { type => 'integer', min => 1 },
        },
        controller => 'Server',
        swagger => { summary => 'Получить список серверов' },
    },
    PUT => {
        controller => 'Server',
        swagger => { summary => 'Создать сервер' },
    },
    POST => {
        controller => 'Server',
        swagger => { summary => 'Изменить сервер' },
    },
    DELETE => {
        params => {
            server_id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Server',
        swagger => { summary => 'Удалить сервер' },
    },
},
'/admin/server/group' => {
    swagger => { tags => 'Группы серверов' },
    GET => {
        params => {
            group_id  => { type => 'integer', min => 1 },
        },
        controller => 'ServerGroups',
        swagger => { summary => 'Получить список групп серверов' },
    },
    PUT => {
        controller => 'ServerGroups',
        swagger => { summary => 'Создать группу серверов' },
    },
    POST => {
        controller => 'ServerGroups',
        swagger => { summary => 'Изменить группу серверов' },
    },
    DELETE => {
        params => {
            group_id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'ServerGroups',
        swagger => { summary => 'Удалить группу серверов' },
    },
},
'/admin/server/identity' => {
    swagger => { tags => 'Ключи SSH' },
    GET => {
        params => {
            id     => { type => 'integer', min => 1 },
        },
        controller => 'Identities',
        swagger => { summary => 'Список SSH ключей' },
    },
    PUT => {
        controller => 'Identities',
        swagger => { summary => 'Сохранить новый SSH ключ' },
    },
    POST => {
        controller => 'Identities',
        swagger => { summary => 'Изменить SSH ключ' },
    },
    DELETE => {
        params => {
            id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Identities',
        swagger => { summary => 'Удалить SSH ключ' },
    },
},
'/admin/server/identity/generate' => {
    swagger => { tags => 'Ключи SSH' },
    GET => {
        params => {
            type => { type => 'string', enum => ['rsa','dsa','ecdsa','ed25519'] },
        },
        controller => 'Identities',
        method => 'generate_key_pair',
        swagger => { summary => 'Сгенерировать SSH ключи' },
    },
},
'/admin/spool' => {
    swagger => { tags => 'Задачи' },
    GET => {
        params => {
            id              => { type => 'integer', min => 1 },
            user_id         => { type => 'integer', min => 1 },
            user_service_id => { type => 'integer', min => 1 },
            status          => { type => 'string' },
        },
        controller => 'Spool',
        swagger => { summary => 'Список текущих задач' },
    },
    PUT => {
        controller => 'Spool',
        swagger => { summary => 'Создать задачу' },
    },
    POST => {
        controller => 'Spool',
        swagger => { summary => 'Изменить задачу' },
    },
    DELETE => {
        params => {
            id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Spool',
        swagger => { summary => 'Удалить задачу' },
    },
},
'/admin/spool/statuses' => {
    swagger => { tags => 'Задачи' },
    GET => {
        params => {},
        controller => 'Spool',
        method => 'statuses',
        swagger => { summary => 'Статусы задач' },
    },
},
'/admin/spool/history' => {
    swagger => { tags => 'Задачи' },
    GET => {
        controller => 'SpoolHistory',
        swagger => { summary => 'Список архива задач' },
    },
},
'/admin/spool/manual/*' => {
    swagger => { tags => 'Задачи' },
    splat_to => 'action',
    POST => {
        params => {
            id => { type => 'integer', required => 1, min => 1 },
            action => { type => 'string', enum => ['success','pause','retry'] },
        },
        controller => 'Spool',
        method => 'api_manual_action',
        swagger => { summary => 'Изменить статус задачи вручную' },
    },
},
'/admin/template' => {
    swagger => { tags => 'Шаблоны' },
    GET => {
        params => {
            id => { type => 'string', min => 1 },
        },
        controller => 'Template',
        method => 'list',
        swagger => { summary => 'Список шаблонов' },
    },
    PUT => {
        controller => 'Template',
        allow_text_plain => 1,
        swagger => { summary => 'Создать шаблон' },
        args => {
            format => 'plain',
        },
    },
    POST => {
        controller => 'Template',
        allow_text_plain => 1,
        swagger => { summary => 'Изменить шаблон ' },
        args => {
            format => 'plain',
        },
    },
    DELETE => {
        params => {
            id => { type => 'string', required => 1, min => 1 },
        },
        controller => 'Template',
        swagger => { summary => 'Удалить шаблон' },
    },
},
'/admin/template/*' => {
    swagger => { tags => 'Шаблоны' },
    splat_to => 'id',
    GET => {
        params => {
            id  => { type => 'string', required => 1, min => 1 },
        },
        controller => 'Template',
        method => 'parse_for_api',
        args => {
            format => 'plain',
            do_not_parse => 1,
        },
        swagger => { summary => 'Прочитать шаблон' },
    },
    PUT => {
        controller => 'Template',
        args => {
            format => 'plain',
        },
    },
    POST => {
        controller => 'Template',
        args => {
            format => 'plain',
        },
    },
    DELETE => {
        params => {
            id  => { type => 'string', required => 1, min => 1 },
        },
        controller => 'Template',
    },
},
'/admin/storage/manage' => {
    swagger => { tags => 'Хранилище' },
    GET => {
        params => {
            user_id => { type => 'integer', min => 1 },
            name    => { type => 'string', max_length => 255 },
        },
        controller => 'Storage',
        swagger => { summary => 'Получить список объектов хранилища' },
    },
    PUT => {
        controller => 'Storage',
        swagger => { summary => 'Создать объект в хранилище' },
    },
    POST => {
        controller => 'Storage',
        method => 'replace',
        swagger => { summary => 'Изменить данные в объекте хранилища' },
    },
    DELETE => {
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
            name    => { type => 'string', required => 1, min_length => 1, max_length => 255 },
        },
        controller => 'Storage',
        method => 'delete',
        swagger => { summary => 'Удалить объект из хранилища' },
    },
},
'/admin/storage/manage/*' => {
    swagger => { tags => 'Хранилище' },
    splat_to => 'name',
    GET => {
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
            name => { type => 'string', required => 1, min_length => 1, max_length => 32 },
        },
        controller => 'Storage',
        method => 'read',
        args => {
            format => 'other',
        },
        swagger => { summary => 'Получить объект хранилища' },
    },
    POST => {
        controller => 'Storage',
        method => 'replace',
    },
    DELETE => {
        params => {
            user_id => { type => 'integer', required => 1, min => 1 },
            name => { type => 'string', required => 1, min_length => 1, max_length => 32 },
        },
        controller => 'Storage',
        method => 'delete',
    },
},
'/admin/config' => {
    swagger => { tags => 'Конфигурация' },
    GET => {
        params => {
            key    => { type => 'string', max_length => 128 },
        },
        controller => 'Config',
        swagger => { summary => 'Прочитать весь конфиг' },
    },
    PUT => {
        controller => 'Config',
        swagger => { summary => 'Создать объект в конфиге' },
    },
    POST => {
        controller => 'Config',
        swagger => { summary => 'Изменить объект в конфиге' },
    },
    DELETE => {
        params => {
            key => { type => 'string', required => 1, min_length => 1, max_length => 128 },
        },
        controller => 'Config',
        swagger => { summary => 'Удалить объект в конфиге' },
    },
},
'/admin/config/*' => {
    swagger => { tags => 'Конфигурация' },
    splat_to => 'key',
    GET => {
        params => {},
        controller => 'Config',
        method => 'api_data_by_name',
        swagger => { summary => 'Получить объект конфига' },
    },
    POST => {
        controller => 'Config',
        params => {},
        method => 'api_set_value',
        skip_auto_parse_json => 1,
        swagger => { summary => 'Изменить объект в конфиге' },
    },
    DELETE => {
        params => {
            value => { type => 'string', required => 1, min_length => 1, max_length => 256 },
        },
        controller => 'Config',
        method => 'api_delete_value',
        swagger => { summary => 'Удалить значение или объект внутри объекта конфига' },
    },
},
'/admin/console' => {



},
'/admin/transport/ssh/test' => {
    PUT => {
        params => {
            host   => { type => 'string', required => 1, min_length => 1, max_length => 255 },
            key_id => { type => 'integer', required => 1, min => 1 },
            server_id => { type => 'integer', required => 1, min => 1 },
            template_id => { type => 'string', min_length => 1 },
            cmd => { type => 'string', min_length => 1 },
            event_name => { type => 'string', min_length => 1},
            timeout => { type => 'integer', min => 1, default => 600 },
        },
        controller => 'Transport::Ssh',
        method => 'ssh_test',
    },
},
'/admin/transport/ssh/init' => {
    PUT => {
        params => {
            host        => { type => 'string', required => 1, min_length => 1, max_length => 255 },
            key_id      => { type => 'integer', required => 1, min => 1 },
            server_id => { type => 'integer', required => 1, min => 1 },
            template_id => { type => 'string', min_length => 1 },
            cmd => { type => 'string', min_length => 1 },
            event_name => { type => 'string', min_length => 1},
            timeout => { type => 'integer', min => 1, default => 600 },
        },
        controller => 'Transport::Ssh',
        method => 'ssh_init',
    },
},
'/admin/promo' => {
    swagger => { tags => 'Промокоды' },
    GET => {
        params => {
            id     => { type => 'integer', min => 1 },
        },
        controller => 'Promo',
        swagger => { summary => 'Список промокодов' },
    },
    PUT => {
        controller => 'Promo',
        method => 'generate',
        swagger => { summary => 'Генерация промокодов' },
    },
    POST => {
        controller => 'Promo',
        method => 'update',
        swagger => { summary => 'Изменить промокод' },
    },
    DELETE => {
        params => {
            id => { type => 'integer', required => 1, min => 1 },
        },
        controller => 'Promo',
        method => 'delete',
        swagger => { summary => 'Удалить промокод' },
    },
},
'/admin/promo/*' => {
    POST => {
        controller => 'Promo',
        method => 'update',
    },
    DELETE => {
        controller => 'Promo',
        method => 'delete',
    },
},
'/admin/analytics' => {
    GET => {
        params => {
            months => { type => 'integer' },
            no_cache => { type => 'boolean' },
        },
        controller => 'Analytics',
        method => 'api_report',
    },
},
'/admin/analytics/cache/clear' => {
    POST => {
        params => {},
        controller => 'Analytics',
        method => 'clear_cache',
    },
},
'/telegram/user' => {
    swagger => {
        tags => 'Telegram bot',
    },
    GET => {
        params => {},
        controller => 'Transport::Telegram',
        method => 'user_tg_settings',
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Получить настройки пользователя для Telegram бота',
        },
    },
    POST => {
        params => {},
        controller => 'Transport::Telegram',
        method => 'api_set_user_tg_settings',
        skip_auto_parse_json => 1,
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Изменить настройки пользователя для Telegram бота',
        },
    },
    DELETE => {
        params => {},
        controller => 'Transport::Telegram',
        method => 'api_delete_user_tg_settings',
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Удалить (отвязать) Telegram аккаунт пользователя',
        },
    },
},
'/telegram/bot' => {
    POST => {
        params => {
            # Telegram Update object fields (https://core.telegram.org/bots/api#update)
            tg_profile              => { type => 'string' },
            update_id               => { type => 'integer', min => 1 },
            message                 => { type => 'object' },
            edited_message          => { type => 'object' },
            channel_post            => { type => 'object' },
            edited_channel_post     => { type => 'object' },
            business_connection     => { type => 'object' },
            business_message        => { type => 'object' },
            edited_business_message => { type => 'object' },
            deleted_business_messages => { type => 'object' },
            guest_message           => { type => 'object' },
            message_reaction        => { type => 'object' },
            message_reaction_count  => { type => 'object' },
            inline_query            => { type => 'object' },
            chosen_inline_result    => { type => 'object' },
            callback_query          => { type => 'object' },
            shipping_query          => { type => 'object' },
            pre_checkout_query      => { type => 'object' },
            purchased_paid_media    => { type => 'object' },
            poll                    => { type => 'object' },
            poll_answer             => { type => 'object' },
            my_chat_member          => { type => 'object' },
            chat_member             => { type => 'object' },
            chat_join_request       => { type => 'object' },
            chat_boost              => { type => 'object' },
            removed_chat_boost      => { type => 'object' },
            managed_bot             => { type => 'object' },
        },
        skip_check_auth => 1,
        skip_errors => 1, # do not send report errors to TG API
        controller => 'Transport::Telegram',
        method => 'process_message',
        args => {
            format => 'json',
        },
    },
},
'/telegram/bot/*' => {
    swagger => {
        tags => 'Telegram bot',
    },
    splat_to => 'template',
    POST => {
        params => {
            # Telegram Update object fields (https://core.telegram.org/bots/api#update)
            tg_profile              => { type => 'string' },
            update_id               => { type => 'integer', min => 1 },
            message                 => { type => 'object' },
            edited_message          => { type => 'object' },
            channel_post            => { type => 'object' },
            edited_channel_post     => { type => 'object' },
            business_connection     => { type => 'object' },
            business_message        => { type => 'object' },
            edited_business_message => { type => 'object' },
            deleted_business_messages => { type => 'object' },
            guest_message           => { type => 'object' },
            message_reaction        => { type => 'object' },
            message_reaction_count  => { type => 'object' },
            inline_query            => { type => 'object' },
            chosen_inline_result    => { type => 'object' },
            callback_query          => { type => 'object' },
            shipping_query          => { type => 'object' },
            pre_checkout_query      => { type => 'object' },
            purchased_paid_media    => { type => 'object' },
            poll                    => { type => 'object' },
            poll_answer             => { type => 'object' },
            my_chat_member          => { type => 'object' },
            chat_member             => { type => 'object' },
            chat_join_request       => { type => 'object' },
            chat_boost              => { type => 'object' },
            removed_chat_boost      => { type => 'object' },
            managed_bot             => { type => 'object' },
        },
        skip_check_auth => 1,
        skip_errors => 1, # do not send report errors to TG API
        controller => 'Transport::Telegram',
        method => 'process_message',
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Приём данных от Telegram',
        },
    },
},
'/telegram/set_webhook' => {
    POST => {
        params => {
            url         => { type => 'string', required => 1, min_length => 1, max_length => 2048 },
            token       => { type => 'string', required => 1, min_length => 1, max_length => 128 },
            secret      => { type => 'string', required => 1, min_length => 1, max_length => 128 },
            template_id => { type => 'string', required => 1, min_length => 1 },
            tg_profile  => { type => 'string', required => 1, min_length => 1 },
            allowed_updates => { type => 'object' },
        },
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'set_webhook',
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Установка Webhook в Telegram бота',
        },
    },
},
'/telegram/webapp/auth' => {
    swagger => {
        tags => 'Telegram bot',
    },
    GET => {
        params => {
            initData => { type => 'string', required => 1, min_length => 1, max_length => 4096 },
            profile => { type => 'string', required => 1, min_length => 1, max_length => 32 },
        },
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'webapp_auth',
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Авторизация Telegram',
             responses => {
                '200' => {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                properties => {
                                    session_id => {
                                        type => 'string'
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
},
'/telegram/web/auth' => {
    swagger => {
        tags => 'Telegram bot',
    },
    POST => {
        params => {
            profile          => { type => 'string' },
            register_if_not_exists => { type => 'boolean' },
            bind_to_profile  => { type => 'boolean' },
            bind_only_if_new => { type => 'boolean' },
            uid              => { type => 'integer', min => 1 },
            # OIDC code flow
            code             => { type => 'string' },
            redirect_uri     => { type => 'string' },
            code_verifier    => { type => 'string' },
            client_id        => { type => 'string' },
            client_secret    => { type => 'string' },
            state            => { type => 'string' },
            expected_state   => { type => 'string' },
            id_token         => { type => 'string' },
            nonce            => { type => 'string' },
            # Legacy widget fields
            id               => { type => 'string' },
            first_name       => { type => 'string' },
            last_name        => { type => 'string' },
            username         => { type => 'string' },
            photo_url        => { type => 'string' },
            auth_date        => { type => 'string' },
            hash             => { type => 'string' },
            query            => { type => 'string' },
        },
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'web_auth',
        swagger => {
            summary => 'Авторизация через Telegram Login (OIDC id_token или legacy Widget)',
             responses => {
                '200' => {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                properties => {
                                    session_id => {
                                        type => 'string'
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
},
'/telegram/web/auth/init' => {
    swagger => {
        tags => 'Telegram bot',
    },
    GET => {
        params => {
            profile                => { type => 'string' },
            redirect_uri           => { type => 'string' },
            return_url             => { type => 'string' },
            scope                  => { type => 'string' },
            register_if_not_exists => { type => 'boolean' },
            bind_to_profile        => { type => 'boolean' },
            bind_only_if_new       => { type => 'boolean' },
            uid                    => { type => 'integer', min => 1 },
            ttl                    => { type => 'integer', min => 1 },
        },
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'telegram_oidc_init',
        swagger => {
            summary => 'Инициализация Telegram Login OIDC (state, nonce, PKCE)',
            responses => {
                '200' => {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                properties => {
                                    auth_url => { type => 'string' },
                                    state => { type => 'string' },
                                    nonce => { type => 'string' },
                                    code_challenge => { type => 'string' },
                                    code_challenge_method => { type => 'string' },
                                    redirect_uri => { type => 'string' },
                                    expires_in => { type => 'number' },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
},
'/telegram/web/auth/start' => {
    swagger => {
        tags => 'Telegram bot',
    },
    GET => {
        params => {
            profile                => { type => 'string' },
            redirect_uri           => { type => 'string' },
            return_url             => { type => 'string' },
            scope                  => { type => 'string' },
            register_if_not_exists => { type => 'boolean' },
            bind_to_profile        => { type => 'boolean' },
            bind_only_if_new       => { type => 'boolean' },
            uid                    => { type => 'integer', min => 1 },
            ttl                    => { type => 'integer', min => 1 },
        },
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'telegram_oidc_start_redirect',
        swagger => {
            summary => 'Старт Telegram Login OIDC с HTTP redirect на Telegram OAuth',
            responses => {
                '302' => {
                    description => 'Redirect to Telegram OAuth',
                },
            },
        },
    },
},
'/telegram/web/callback' => {
    swagger => {
        tags => 'Telegram bot',
    },
    GET => {
        params => {
            profile                => { type => 'string' },
            register_if_not_exists => { type => 'boolean' },
            bind_to_profile        => { type => 'boolean' },
            bind_only_if_new       => { type => 'boolean' },
            uid                    => { type => 'integer', min => 1 },
            # OIDC code flow
            code                   => { type => 'string' },
            redirect_uri           => { type => 'string' },
            return_url             => { type => 'string' },
            code_verifier          => { type => 'string' },
            state                  => { type => 'string' },
            expected_state         => { type => 'string' },
            client_id              => { type => 'string' },
            client_secret          => { type => 'string' },
            id_token               => { type => 'string' },
            nonce                  => { type => 'string' },
        },
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'web_auth_callback',
        swagger => {
            summary => 'Callback endpoint для Telegram Login (OIDC code flow)',
            responses => {
                '200' => {
                    content => {
                        'application/json' => {
                            schema => {
                                type => 'object',
                                properties => {
                                    session_id => {
                                        type => 'string'
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
},
'/admin/cloud/user' => {
    GET => {
        params => {},
        controller => 'Cloud',
        method => 'get_user',
    },
    PUT => {
        params => {
            login          => { type => 'string', required => 1, min_length => 1, max_length => 128 },
            password       => { type => 'string', required => 1, min_length => 1, max_length => 128 },
            captcha_token  => { type => 'string' },
            captcha_answer => { type => 'string' },
        },
        controller => 'Cloud',
        method => 'reg_user',
    },
},
'/admin/cloud/user/auth' => {
    swagger => {
        tags => 'Cloud SHM',
    },
    POST => {
        params => {
            login    => { type => 'string', required => 1, min_length => 1, max_length => 128 },
            password => { type => 'string', required => 1, min_length => 1, max_length => 128 },
        },
        controller => 'Cloud',
        method => 'login_user',
    },
    DELETE => {
        params => {},
        controller => 'Cloud',
        method => 'logout_user',
    },
},
'/admin/cloud/paysystems' => {
    GET => {
        params => {},
        controller => 'Cloud',
        method => 'paysystems',
    },
},
'/admin/cloud/currencies' => {
    GET => {
        params => {
            no_cache => { type => 'boolean' },
        },
        controller => 'Cloud::Currency',
        method => 'currencies',
    },
    POST => {
        params => {
            currencies => { type => 'object', required => 1 },
        },
        controller => 'Cloud::Currency',
        method => 'save',
    },
},
'/admin/cloud/proxy/*' => {
    splat_to => 'uri',
    GET => {
        params => {},
        controller => 'Cloud',
        method => 'proxy',
        args => {
            format => 'json',
        },
    },
    POST => {
        params => {},
        controller => 'Cloud',
        method => 'proxy',
        args => {
            format => 'json',
        },
    },
    PUT => {
        params => {},
        controller => 'Cloud',
        method => 'proxy',
        args => {
            format => 'json',
        },
    },
    DELETE => {
        params => {},
        controller => 'Cloud',
        method => 'proxy',
        args => {
            format => 'json',
        },
    },
}

};

$routes->{'/swagger.json'} //= {
    GET => {
        params => {},
        controller => 'Swagger',
        method => 'gen_swagger_json',
        skip_check_auth => 1,
        args => {
            routes => $routes,
            format => 'json',
        },
    },
};

$routes->{'/swagger_admin.json'} //= {
    GET => {
        params => {},
        controller => 'Swagger',
        method => 'gen_swagger_json',
        skip_check_auth => 1,
        args => {
            routes => $routes,
            admin_mode => 1,
            format => 'json',
        },
    },
};

state $router //= Router::Simple->new();
for my $uri ( keys %{ $routes } ) {
    for my $method ( 'GET','POST','PUT','DELETE' ) {
        next unless $routes->{$uri}->{$method};
        $routes->{$uri}->{$method}->{splat_to} = $routes->{$uri}->{splat_to} if $routes->{$uri}->{splat_to};
        $router->connect( sprintf("%s:%s", $method, $uri), $routes->{$uri}->{$method} );
    }
}

my $uri = $ENV{PATH_INFO};
our %in;

if ( my $p = $router->match( sprintf("%s:%s", $ENV{REQUEST_METHOD}, $uri )) ) {

    %in = parse_args( auto_parse_json => $p->{skip_auto_parse_json} ? 0 : 1 );
    $in{filter} = decode_json( $in{filter} ) if $in{filter};

    if ( my $splat = $p->{splat} ) {
        $in{ $p->{splat_to} || 'id' } = $splat->[0];
    }

    my $user = SHM->new(
        skip_check_auth => $p->{skip_check_auth},
        user_id => $p->{user_id},
    );

    if ( $user->is_blocked ) {
        print_header( status => 403 );
        print_json( { status => 403, error => "User is blocked"} );
        exit 0;
    }

    my $admin_mode;
    if ( $uri =~/^\/admin\// ) {
        unless ( $user->is_admin ) {
            print_header( status => 403 );
            print_json( { status => 403, error => "Permission denied"} );
            exit 0;
        }
        $admin_mode = 1;
    }

    my %args = (
        %{ $p->{args} || {} },
        %in,
        admin => $admin_mode,
    );

    if ( $user->is_admin && $args{user_id} ) {
        switch_user( $args{user_id} );
    } else {
        delete $args{user_id};
    }

    my $service = get_service( $p->{controller} );
    unless ( $service ) {
        print_header( status => 404 );
        print_json( { error => 'Ресурс не найден'} );
        exit 0;
    }

    # If params is explicitly defined in route (even as empty {}), use it as-is.
    # If params is not defined at all, auto-populate from controller structure.
    my %schema;
    if ( exists $p->{params} ) {
        %schema = %{ $p->{params} };
    } elsif ( $service->can('structure') ) {
        my $structure = $service->structure;
        for my $field ( keys %{ $structure } ) {
            my $type = $structure->{ $field }->{type} // 'string';
            $type = 'object' if $type eq 'json';
            $type = 'string' if $type =~ /^(?:text|now|date)$/;
            $schema{ $field } = { type => $type };
        }
    }

    # For GET list_for_api endpoints, inject common list params into schema so
    # they pass validation and are forwarded to the controller.
    if ( $ENV{REQUEST_METHOD} eq 'GET' && ( !$p->{method} || $p->{common_params} ) ) {
        my %_common = (
            field  => { type => 'string',  pattern => '^\w+' },
            sort_field => {type => 'string', pattern => '^\w+' },
            sort_direction => { type => 'enum', enum => ['desc','asc'] },
            start  => { type => 'string', pattern => '^\d{4}-\d{2}-\d{2}' },
            stop   => { type => 'string', pattern => '^\d{4}-\d{2}-\d{2}' },
            limit  => { type => 'integer', min => 0, max => 10000 },
            offset => { type => 'integer', min => 0 },
            filter => { type => 'string' },
        );

        for my $f ( keys %_common ) {
            $schema{$f} //= $_common{$f};
        }
    }

    my $method = $p->{method};
    $method ||= 'list_for_api'  if $ENV{REQUEST_METHOD} eq 'GET';
    $method ||= 'api_set'       if $ENV{REQUEST_METHOD} eq 'POST';
    $method ||= 'api_add'       if $ENV{REQUEST_METHOD} eq 'PUT';
    $method ||= 'delete'        if $ENV{REQUEST_METHOD} eq 'DELETE';

    my %allowed_input_fields = map { $_ => 1 } (
        keys %schema,
        'dry_run',
        'POSTDATA',
        'PUTDATA',
        ( $p->{splat_to} ? $p->{splat_to} : () ),
    );
    if ( my $err = validate_params( \%schema, \%args, \%allowed_input_fields ) ) {
        print_header( status => 400 );
        print_json( { status => 400, error => $err } );
        get_service('logger')->warning( sprintf("API validation error: %s %s::%s => %s",
            $ENV{REQUEST_METHOD},
            ref $service,
            $method,
            $err
        ));
        exit 0;
    }

    # Build safe_args: route-level defaults + only declared/validated input fields.
    # Any %in field not listed in params or optional is silently dropped.
    # Use %args (not %in) so that type-coerced values (int, number) are used.
    my %safe_args = (
        %{ $p->{args} || {} },
        $admin_mode ? ( admin => $admin_mode ) : (),
    );
    for my $field ( keys %in ) {
        $safe_args{$field} = $args{$field} if $allowed_input_fields{$field};
    }
    # Preserve user_id context if admin switched user (already processed above)
    $safe_args{user_id} = $args{user_id} if $admin_mode && exists $args{user_id};

    unless ( $service->can( $method ) ) {
        print_header( status => 500 );
        print_json( { status => 500, error => 'Method not exists'} );
    }

    our $last_cache_reset //= time();
    our $cache_reset_interval //= 10;

    if ( my $cache = get_service('Core::System::Cache') ) {
        my $ip = get_user_ip();
        my $tag = lc sprintf("%s-%s-%s", ref $service, $method, $ip);
        if ( $cache->get( $tag ) >= 5 ) {
            get_service('logger')->error("API rejected for tag: $tag");
            print_header( status => 429 );
            print_json( { status => 429, error => '429 Too Many Requests', ip => $ip } );
            exit 0;
        }

        # Cache reset operations with rate limiting (max 1 per 10 seconds per worker)
        my $now = time();
        if ($now - $last_cache_reset >= $cache_reset_interval) {
            my %resets = $cache->redis->hgetall('SHM:Cache:Reset');
            for my $item ( keys %resets ) {
                my $reset_ts = $resets{$item};
                next if $reset_ts < $last_cache_reset;
                my $reset_service = get_service( $item ) || next;
                $reset_service->unregister_child();
                Core::System::ServiceManager::setup() if $item eq 'Core::Config';
                get_service('logger')->info("Worker PID=$$ Reset cache for $item");
            }

            # Always update last check time after interval passes
            # Set -1 sec to prevent race conditions
            $last_cache_reset = $now - 1;
        }
    }

    my @data;
    my %headers;
    my %info;

    if ( $ENV{REQUEST_METHOD} eq 'GET' ) {
        @data = $service->$method( %safe_args );
        %info = (
            items => $service->found_rows(),
            limit => $in{limit} || 25,
            offset => $in{offset} || 0,
            $safe_args{filter} ? (filter => $safe_args{filter}) : (),
        );
    } elsif ( $ENV{REQUEST_METHOD} eq 'PUT' ) {
        my $ret = $service->$method( %safe_args );
        if ( length $ret ) {
            if ( ref $ret eq 'HASH' ) {
                push @data, $ret;
            } elsif ( ref $ret eq 'ARRAY' ) {
                @data = @{ $ret };
            } elsif ( blessed $ret ) {
                @data = scalar $ret->get;
            } else {
                if ( my $obj = $service->id( $ret ) ) {
                    @data = scalar $obj->get;
                } else {
                    $headers{status} = 409;
                    $info{error} = "Can't create a service";
                }
            }
        }
        else {
            $headers{status} = 400;
            $info{error} = "Can't add a new object. Perhaps it already exists?";
        }
    } elsif ( $ENV{REQUEST_METHOD} eq 'POST' || $ENV{REQUEST_METHOD} eq 'DELETE' ) {
        if ( $user->id && $service->can('structure') ) {
            if ( $service = $service->id( get_service_id( $service, %safe_args ) ) ) {
                if ( $service->lock( timeout => 3 )) {
                    push @data, $service->$method( %safe_args );
                } else {
                    $headers{status} = 408;
                    $info{error} = "The service is locked. Try again later.";
                }
            } else {
                $headers{status} = 404;
                $info{error} = "Object not found. Check the ID.";
            }
        } elsif ( $service->can( $method ) ) {
            push @data, $service->$method( %safe_args );
        } else {
            $headers{status} = 400;
            $info{error} = "Unknown error";
        }
    } else {
            $headers{status} = 400;
            $info{error} = "Unknown REQUEST_METHOD";
    };

    my $report = get_service('report');
    unless ( $report->is_success || $p->{skip_errors} ) {
        my %headers = $report->headers;
        $headers{status} ||= 400;
        print_header( %headers );
        my ( $err_msg ) = $report->errors;
        print_json( { status => $headers{status}, error => $err_msg } );
        exit 0;
    }

    if ( $service ) {
        $service->remove_protected_fields( \@data, admin => $user->is_admin );
    }

    if ( $safe_args{format} eq 'plain' || $safe_args{format} eq 'html' ) {
        print_header( %headers, type => "text/$safe_args{format}" );
        for ( @data ) {
            unless ( ref ) {
                utf8::encode($_);
                print;
            } else {
                print encode_json( $_ );
            }
        }
    } elsif ( $safe_args{format} eq 'json' ) {
        print_header( %headers, type => "application/json" );
        for ( @data ) {
            unless ( ref ) {
                utf8::encode($_);
                print;
            } else {
                print encode_json( $_ );
            }
        }
    } elsif ( $safe_args{format} eq 'other' ) {
        print_header( %headers,
            type => 'application/octet-stream',
            $safe_args{filename} ? ('Content-Disposition' => "attachment; filename=$safe_args{filename}") : (),
        );
        for ( @data ) {
            unless ( ref ) {
                utf8::encode($_);
                print;
            } else {
                print encode_json( $_ );
            }
        }
    } elsif ( $safe_args{format} eq 'qrcode' ) {
        print_header( %headers,
            type => 'image/svg+xml',
        );
        my $data = join('', @data);
        my $result = qrencode($data, format => 'SVG');
        print $result->{data} if $result->{success};
    } elsif ( $safe_args{format} eq 'qrcode_png' ) {
        print_header( %headers,
            type => 'image/png',
        );
        my $data = join('', @data);
        my $result = qrencode($data, format => 'PNG');
        print $result->{data} if $result->{success};
    } elsif ( $info{error} ) {
        print_header( %headers );
        print_json({
            %info,
            status => $headers{status},
        });
    } else {
        print_header( %headers );
        print_json({
            TZ => $ENV{TZ},
            date => scalar localtime,
            %info,
            data => \@data,
            status => 200,
        });
    }

    if ( $in{dry_run} ) {
        $user->rollback();
    } else {
        $user->commit();
    }
} else {
    print_header( status => 404 );
    print_json( { status => 404, error => 'Method not found'} );
}

sub get_service_id {
    my $service = shift;
    my %args = @_;

    my $table_key = $service->get_table_key;
    my $service_id = $args{ $table_key } || $args{id};

    if ( !$service_id && $table_key eq 'user_id' ) {
        $service_id = get_service('user')->id;
    }

    unless ( length $service_id ) {
        print_header( status => 400 );
        print_json( { status => 400, error => sprintf("`%s` not present", $service->get_table_key ) } );
        exit 0;
    }
    return $service_id;
}

# Validate %args against a params schema defined in the route.
# Schema format (per field):
#   type         => 'integer' | 'number' | 'string' | 'email' | 'boolean'
#   required     => 1   (field must be present and non-empty)
#   min / max    => numeric bounds (for integer/number)
#   min_length   => minimum string length
#   max_length   => maximum string length
#   pattern      => regex the value must match (string)
#   enum         => arrayref of allowed values
#
# Returns undef on success, or an error string on the first failing field.
sub validate_params {
    my ( $schema, $args, $allowed_input_fields ) = @_;

    for my $field ( sort keys %{ $schema } ) {
        my $rule  = $schema->{ $field };
        my $value = $args->{ $field };
        my $type  = $rule->{type} // 'string';

        # presence check
        if ( $rule->{required} && ( !defined $value || $value eq '' ) ) {
            return sprintf( "Field required: %s", $field );
        }

        # Skip remaining checks only when field is truly absent.
        # Empty string is treated as provided value and must be validated.
        next unless defined $value;

        # type coercion / check
        if ( $type eq 'integer' ) {
            return sprintf( "Field '%s' must be an integer", $field )
                unless $value =~ /^-?\d+$/;
            $value = int($value);
            $args->{ $field } = $value;
            return sprintf( "Field '%s' must be >= %s", $field, $rule->{min} )
                if defined $rule->{min} && $value < $rule->{min};
            return sprintf( "Field '%s' must be <= %s", $field, $rule->{max} )
                if defined $rule->{max} && $value > $rule->{max};
        }
        elsif ( $type eq 'number' ) {
            return sprintf( "Field '%s' must be a number", $field )
                unless $value =~ /^-?(?:\d+\.?\d*|\.\d+)$/;
            $value = $value + 0;
            $args->{ $field } = $value;
            return sprintf( "Field '%s' must be >= %s", $field, $rule->{min} )
                if defined $rule->{min} && $value < $rule->{min};
            return sprintf( "Field '%s' must be <= %s", $field, $rule->{max} )
                if defined $rule->{max} && $value > $rule->{max};
        }
        elsif ( $type eq 'boolean' ) {
            # Normalize JSON booleans (true → 1, false → 0) and string variants
            if ( ref $value ) {
                $value = $value ? 1 : 0;
                $args->{ $field } = $value;
            } elsif ( $value eq 'true' || $value eq 'false' ) {
                $value = $value eq 'true' ? 1 : 0;
                $args->{ $field } = $value;
            }
            return sprintf( "Field '%s' must be 0 or 1", $field )
                unless $value =~ /^[01]$/;
        }
        elsif ( $type eq 'email' ) {
            return sprintf( "Field '%s' must be a valid email address", $field )
                unless is_email($value) && length($value) <= 254;
        }
        elsif ( $type eq 'object' ) {
            return sprintf( "Field '%s' must be an object", $field )
                unless ref($value) eq 'HASH';
        }
        elsif ( $type eq 'string' ) {
            if ( defined $rule->{min_length} && length($value) < $rule->{min_length} ) {
                return sprintf( "Field '%s' must be at least %d characters", $field, $rule->{min_length} );
            }
            if ( defined $rule->{max_length} && length($value) > $rule->{max_length} ) {
                return sprintf( "Field '%s' must be at most %d characters", $field, $rule->{max_length} );
            }
            if ( defined $rule->{pattern} && $value !~ /$rule->{pattern}/ ) {
                return sprintf( "Field '%s' has an invalid format", $field );
            }
        }

        # enum check (applicable to any type)
        if ( my $enum = $rule->{enum} ) {
            my %allowed = map { $_ => 1 } @{ $enum };
            return sprintf( "Field '%s' must be one of: %s", $field, join(', ', @{ $enum }) )
                unless $allowed{ $value };
        }
    }

    return undef;
}

# exit 0;
