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
    switch_user
    blessed
    print_header
    print_json
    get_user_ip
);

use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;

my $cache = get_service('Core::System::Cache');
if ( $cache->get( get_user_ip() ) > 5 ) {
    print_header( status => 429 );
    print_json( { status => 429, error => '429 Too Many Requests'} );
    exit 0;
}

my $routes = {
'/test' => {
    GET => {
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
'/user' => {
    swagger => { tags => 'Пользователи' },
    GET => {
        controller => 'User',
        swagger => { summary => 'Получение пользователя' },
    },
    PUT => {
        controller => 'User',
        method => 'reg',
        skip_check_auth => 1,
        required => ['login','password'],
        swagger => { summary => 'Регистрация пользователя' },
    },
    POST => {
        controller => 'User',
        swagger => { summary => 'Изменить пользователя' },
    },
},
'/user/auth' => {
    swagger => { tags => 'Пользователи' },
    POST => {
        controller => 'User',
        method => 'api_auth',
        skip_check_auth => 1,
        required => ['login','password'],
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
'/user/passwd' => {
    swagger => { tags => 'Пользователи' },
    POST => {
        swagger => { summary => 'Сменить пароль пользователя' },
        controller => 'User',
        method => 'passwd',
        required => ['password'],
    },
},
'/user/passwd/reset' => {
    POST => {
        controller => 'User',
        method => 'passwd_reset_request',
        skip_check_auth => 1,
        required => ['email'],
    },
},
'/user/service' => {
    swagger => { tags => 'Услуги пользователей' },
    GET => {
        controller => 'USObject',
        optional => ['user_service_id'],
        swagger => { summary => 'Список услуг пользователя' },
    },
    DELETE => {
        controller => 'USObject',
        required => ['user_service_id'],
        swagger => { summary => 'Удалить услугу пользователя' },
    },
},
'/user/service/stop' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'block',
        required => ['user_service_id'],
        swagger => { summary => 'Остановить услугу пользователя' },
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
    DELETE => {
        controller => 'User',
        method => 'delete_autopayment',
        required => [],
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
        controller => 'Pay',
        method => 'forecast',
        swagger => { summary => 'Прогноз оплаты' },
    },
},
'/user/pay/paysystems' => {
    swagger => { tags => 'Платежи' },
    GET => {
        controller => 'Pay',
        method => 'paysystems',
        swagger => { summary => 'Платежные системы' },
    },
},
'/service/order' => {
    swagger => { tags => 'Услуги' },
    GET => {
        controller => 'Service',
        method => 'api_price_list',
        swagger => { summary => 'Список услуг для заказа' },
    },
    PUT => {
        controller => 'USObject',
        method => 'create_for_api_safe',
        required => ['service_id'],
        swagger => { summary => 'Регистрация услуги' },
    },
},
'/service' => {
    swagger => { tags => 'Услуги' },
    GET => {
        swagger => { summary => 'Информация об услуге' },
        controller => 'Service',
        required => ['service_id'],
    },
},
'/template/*' => {
    swagger => { tags => 'Шаблоны' },
    GET => {
        controller => 'Template',
        method => 'show',
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Выполнить шаблон' },
    },
    POST => {
        controller => 'Template',
        method => 'show',
        skip_auto_parse_json => 1,
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Выполнить шаблон с аргументами' },
    },
},
'/public/*' => {
    swagger => { tags => 'Шаблоны' },
    GET => {
        user_id => 1,
        controller => 'Template',
        method => 'show_public',
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Выполнить публичный шаблон' },
    },
    POST => {
        user_id => 1,
        controller => 'Template',
        method => 'show_public',
        skip_auto_parse_json => 1,
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Выполнить публичный шаблон с аргументами' },
    },
},
'/storage/manage' => {
    swagger => { tags => 'Хранилище' },
    GET => {
        controller => 'Storage',
        swagger => { summary => 'Список данных' },
    },
    PUT => {
        controller => 'Storage',
        swagger => { summary => 'Создать данные в хранилище' },
    },
    POST => {
        controller => 'Storage',
        swagger => { summary => 'Изменить данные в хранилище' },
    },
    DELETE => {
        controller => 'Storage',
        required => ['name'],
        swagger => { summary => 'Удалить данные в хранилище' },
    },
},
'/storage/manage/*' => {
    swagger => { tags => 'Хранилище' },
    splat_to => 'name',
    GET => {
        controller => 'Storage',
        method => 'read',
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Прочитать данные из хранилища' },
    },
    PUT => {
        controller => 'Storage',
        method => 'add',
        skip_auto_parse_json => 1,
        allow_text_plain => 1,
        required => [],
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Создать данные в хранилище' },
    },
    POST => {
        controller => 'Storage',
        method => 'replace',
        skip_auto_parse_json => 1,
        allow_text_plain => 1,
        required => [],
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Изменить данные в хранилище' },
    },
    DELETE => {
        controller => 'Storage',
        method => 'delete',
        required => [],
        swagger => { summary => 'Удалить данные из хранилища' },
    },
},
'/storage/download/*' => {
    swagger => { tags => 'Хранилище' },
    splat_to => 'name',
    GET => {
        controller => 'Storage',
        method => 'download',
        args => {
            format => 'plain',
        },
        swagger => { summary => 'Скачать данные из хранилища' },
    },
},

'/admin/service' => {
    swagger => { tags => 'Услуги' },
    GET => {
        controller => 'Service',
        swagger => { summary => 'Получить услугу' },
    },
    PUT => {
        controller => 'Service',
        swagger => { summary => 'Создать услуг' },
    },
    POST => {
        controller => 'Service',
        required => ['service_id'],
        swagger => { summary => 'Изменить услугу' },
    },
    DELETE => {
        controller => 'Service',
        required => ['service_id'],
        swagger => { summary => 'Удалить услугу' },
    },
},
'/admin/service/order' => {
    swagger => { tags => ['Услуги','Услуги пользователей'] },
    GET => {
        controller => 'Service',
        method => 'api_price_list',
        swagger => { summary => 'Список услуг доступных для регистрации' },
    },
    PUT => {
        controller => 'USObject',
        method => 'create_for_api',
        required => ['user_id','service_id','cost','months','settings'],
        swagger => { summary => 'Зарегистрировать услугу клиенту' },
    },
},
'/admin/service/children' => {
    swagger => { tags => 'Услуги' },
    GET => {
        controller => 'Service',
        method => 'api_subservices_list',
        required => ['service_id'],
        swagger => { summary => 'Список дочерних услуг' },
    },
    POST => {
        controller => 'Service',
        method => 'children',
        required => ['service_id', 'children'],
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
        controller => 'Events',
        required => ['id'],
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
        required => ['login','password'],
        swagger => { summary => 'Создать клиента' },
    },
    POST => {
        controller => 'User',
        required => ['user_id'],
        swagger => { summary => 'Изменить клиента' },
    },
    DELETE => {
        controller => 'User',
        required => ['user_id'],
        swagger => { summary => 'Удалить клиента' },
    },
},
'/admin/user/passwd' => {
    swagger => { tags => 'Пользователи' },
    POST => {
        controller => 'User',
        method => 'passwd',
        required => ['user_id','password'],
        swagger => { summary => 'Сменить пароль клиенту' },
    },
},
'/admin/user/payment' => {
    swagger => { tags => 'Пользователи' },
    PUT => {
        controller => 'User',
        method => 'payment',
        required => ['user_id','money'],
        swagger => { summary => 'Зачислить деньги клиенту' },
    },
},
'/admin/user/profile' => {
    GET => {
        controller => 'Profile',
    },
    PUT => {
        controller => 'Profile',
    },
    POST => {
        controller => 'Profile',
    },
    DELETE => {
        controller => 'Profile',
    },
},
'/admin/user/pay' => {
    swagger => { tags => 'Платежи' },
    GET => {
        controller => 'Pay',
        swagger => { summary => 'Список платежей клиентов' },
    },
    PUT => {
        controller => 'Pay',
        swagger => { summary => 'Создать платеж' },
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
        controller => 'Bonus',
        required => ['id','user_id'],
        swagger => { summary => 'Изменить бонус' },
    },
},
'/admin/user/service' => {
    swagger => { tags => 'Услуги пользователей' },
    GET => {
        controller => 'UserService',
        swagger => { summary => 'Список услуг клиентов' },
    },
    PUT => {
        controller => 'USObject',
    },
    POST => {
        controller => 'USObject',
        required => ['user_id', 'user_service_id'],
        swagger => { summary => 'Изменить услугу клиента' },
    },
    DELETE => {
        controller => 'USObject',
        required => ['user_id', 'user_service_id'],
        swagger => { summary => 'Удалить услугу клиента' },
    },
},
'/admin/user/service/categories' => {
    swagger => { tags => 'Услуги пользователей' },
    GET => {
        controller => 'Service',
        method => 'categories',
        swagger => { summary => 'Получить список категорий услуг' },
    },
},
'/admin/user/service/withdraw' => {
    swagger => { tags => 'Списания' },
    GET => {
        controller => 'Withdraw',
        swagger => { summary => 'Получить список списаний клиентов' },
    },
    PUT => {
        controller => 'Withdraw',
        swagger => { summary => 'Создать списание клиенту' },
    },
    POST => {
        controller => 'Withdraw',
        required => ['user_id', 'withdraw_id'],
        swagger => { summary => 'Изменить списание клиента' },
    },
},
'/admin/user/service/status' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'set_status_manual',
        required => ['user_id','user_service_id','status'],
        swagger => { summary => 'Сменить статус услуги клиента' },
    },
},
'/admin/user/service/stop' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'block_force',
        required => ['user_id','user_service_id'],
        swagger => { summary => 'Остановить услугу клиента' },
    },
},
'/admin/user/service/activate' => {
    swagger => { tags => 'Услуги пользователей' },
    POST => {
        controller => 'USObject',
        method => 'activate_force',
        required => ['user_id','user_service_id'],
        swagger => { summary => 'Возобновить услугу клиента' },
    },
},
'/admin/user/service/spool' => {
    swagger => { tags => ['Услуги пользователей','Задачи'] },
    GET => {
        controller => 'USObject',
        method => 'api_spool_commands',
        required => ['user_id','user_service_id'],
        swagger => { summary => 'Получить список текущих задач для услуги клиента' },
    },
},
'/admin/user/session' => {
    swagger => { tags => 'Пользователи' },
    PUT => {
        controller => 'User',
        method => 'gen_session',
        required => ['user_id'],
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
        controller => 'Server',
        swagger => { summary => 'Получить список серверов' },
    },
    PUT => {
        controller => 'Server',
        swagger => { summary => 'Создать сервер' },
    },
    POST => {
        controller => 'Server',
        required => ['server_id'],
        swagger => { summary => 'Изменить сервер' },
    },
    DELETE => {
        controller => 'Server',
        required => ['server_id'],
        swagger => { summary => 'Удалить сервер' },
    },
},
'/admin/server/group' => {
    swagger => { tags => 'Группы серверов' },
    GET => {
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
        controller => 'ServerGroups',
        required => ['group_id'],
        swagger => { summary => 'Удалить группу серверов' },
    },
},
'/admin/server/identity' => {
    swagger => { tags => 'Ключи SSH' },
    GET => {
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
        controller => 'Identities',
        required => ['id'],
        swagger => { summary => 'Удалить SSH ключ' },
    },
},
'/admin/server/identity/generate' => {
    swagger => { tags => 'Ключи SSH' },
    GET => {
        controller => 'Identities',
        method => 'generate_key_pair',
        swagger => { summary => 'Сгенерировать SSH ключи' },
    },
},
'/admin/spool' => {
    swagger => { tags => 'Задачи' },
    GET => {
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
        controller => 'Spool',
        required => ['id'],
        swagger => { summary => 'Удалить задачу' },
    },
},
'/admin/spool/history' => {
    swagger => { tags => 'Задачи' },
    GET => {
        controller => 'SpoolHistory',
        swagger => { summary => 'Список архива задач' },
    },
},
'/admin/spool/*' => {
    swagger => { tags => 'Задачи' },
    splat_to => 'action',
    POST => {
        controller => 'Spool',
        method => 'api_manual_action',
        required => ['id'],
        swagger => { summary => 'Изменить статус задачи' },
    },
},
'/admin/template' => {
    swagger => { tags => 'Шаблоны' },
    GET => {
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
        controller => 'Template',
        required => ['id'],
        swagger => { summary => 'Удалить шаблон' },
    },
},
'/admin/template/*' => {
    swagger => { tags => 'Шаблоны' },
    splat_to => 'id',
    GET => {
        controller => 'Template',
        method => 'show',
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
        controller => 'Template',
    },
},
'/admin/storage/manage' => {
    swagger => { tags => 'Хранилище' },
    GET => {
        controller => 'Storage',
        swagger => { summary => 'Получить список объектов хранилища' },
    },
    POST => {
        controller => 'Storage',
        method => 'replace',
        swagger => { summary => 'Изменить данные в объекте хранилища' },
    },
    DELETE => {
        controller => 'Storage',
        method => 'delete',
        required => ['user_id','name'],
        swagger => { summary => 'Удалить объект из хранилища' },
    },
},
'/admin/storage/manage/*' => {
    swagger => { tags => 'Хранилище' },
    splat_to => 'name',
    POST => {
        controller => 'Storage',
        method => 'replace',
    },
    DELETE => {
        controller => 'Storage',
        method => 'delete',
        required => ['user_id'],
    },
},
'/admin/config' => {
    swagger => { tags => 'Конфигурация' },
    GET => {
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
        controller => 'Config',
        required => ['key'],
        swagger => { summary => 'Удалить объект в конфиге' },
    },
},
'/admin/config/*' => {
    swagger => { tags => 'Конфигурация' },
    splat_to => 'key',
    GET => {
        controller => 'Config',
        method => 'api_data_by_name',
        swagger => { summary => 'Получить объект конфига' },
    },
},
'/admin/console' => {



},
'/admin/transport/ssh/test' => {
    PUT => {
        controller => 'Transport::Ssh',
        method => 'ssh_test',
        required => [
            'host',
            'key_id',
        ],
    },
},
'/admin/transport/ssh/init' => {
    PUT => {
        controller => 'Transport::Ssh',
        method => 'ssh_init',
        required => [
            'host',
            'key_id',
            'template_id',
        ],
    },
},
'/admin/transport/mail/test' => {
    POST => {

    },
},
'/admin/stats' => {
    swagger => { tags => 'Статистика' },
    GET => {
        controller => 'Stats',
        method => 'dashboard',
        swagger => { summary => 'Панель статистики' },
    },
},
'/telegram/bot' => {
    POST => {
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
'/telegram/webapp/auth' => {
    swagger => {
        tags => 'Telegram bot',
    },
    GET => {
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'webapp_auth',
        required => ['initData'],
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
        skip_check_auth => 1,
        controller => 'Transport::Telegram',
        method => 'web_auth',
        required => ['query'],
        args => {
            format => 'json',
        },
        swagger => {
            summary => 'Авторизация через Telegram Widjet',
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

};

$routes->{'/swagger.json'} = {
    GET => {
        controller => 'Swagger',
        method => 'gen_swagger_json',
        skip_check_auth => 1,
        args => {
            routes => $routes,
            format => 'json',
        },
    },
};

$routes->{'/swagger_admin.json'} = {
    GET => {
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

my $router = Router::Simple->new();
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

    if ( my $r_args = $p->{required} ) {
        for ( @{ $r_args } ) {
            $args{ $_ } = $p->{ $_ } if exists $p->{ $_ };
            unless ( exists $args{ $_ } ) {
                print_header( status => 400 );
                print_json( { status => 400, error => sprintf("Field required: %s", $_) } );
                exit 0;
            }
        }
    }

    my $service = get_service( $p->{controller} );
    unless ( $service ) {
        print_header( status => 500 );
        print_json( { error => 'Недоступно в данной версии'} );
        exit 0;
    }

    my $method = $p->{method};
    $method ||= 'list_for_api'  if $ENV{REQUEST_METHOD} eq 'GET';
    $method ||= 'api_set'       if $ENV{REQUEST_METHOD} eq 'POST';
    $method ||= 'api_add'       if $ENV{REQUEST_METHOD} eq 'PUT';
    $method ||= 'delete'        if $ENV{REQUEST_METHOD} eq 'DELETE';

    unless ( $service->can( $method ) ) {
        print_header( status => 500 );
        print_json( { status => 500, error => 'Method not exists'} );
    }

    my @data;
    my %headers;
    my %info;

    if ( $ENV{REQUEST_METHOD} eq 'GET' ) {
        @data = $service->$method( %args );
        %info = (
            items => $service->found_rows(),
            limit => $in{limit} || 25,
            offset => $in{offset} || 0,
            $args{filter} ? (filter => $args{filter}) : (),
        );
    } elsif ( $ENV{REQUEST_METHOD} eq 'PUT' ) {
        my $ret = $service->$method( %args );
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
        if ( $user->id ) {
            if ( $service = $service->id( get_service_id( $service, %args ) ) ) {
                if ( $service->lock( timeout => 3 )) {
                    push @data, $service->$method( %args );
                } else {
                    $headers{status} = 408;
                    $info{error} = "The service is locked. Try again later.";
                }
            } else {
                $headers{status} = 404;
                $info{error} = "Object not found. Check the ID.";
            }
        } elsif ( $service->can( $method ) ) {
            push @data, $service->$method( %args );
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
        my $status = $report->status || 400;
        print_header( status => $status );
        my ( $err_msg ) = $report->errors;
        print_json( { status => $status, error => $err_msg } );
        exit 0;
    }

    if ( $service ) {
        $service->remove_protected_fields( \@data, admin => $user->is_admin );
    }

    if ( $args{format} eq 'plain' || $args{format} eq 'html' ) {
        print_header( %headers, type => "text/$args{format}" );
        for ( @data ) {
            unless ( ref ) {
                utf8::encode($_);
                print;
            } else {
                print encode_json( $_ );
            }
        }
    } elsif ( $args{format} eq 'json' ) {
        print_header( %headers, type => "application/json" );
        for ( @data ) {
            unless ( ref ) {
                utf8::encode($_);
                print;
            } else {
                print encode_json( $_ );
            }
        }
    } elsif ( $args{format} eq 'other' ) {
        print_header( %headers,
            type => 'application/octet-stream',
            $args{filename} ? ('Content-Disposition' => "attachment; filename=$args{filename}") : (),
        );
        for ( @data ) {
            unless ( ref ) {
                utf8::encode($_);
                print;
            } else {
                print encode_json( $_ );
            }
        }
    } elsif ( $args{format} eq 'qrcode' ) {
        print_header( %headers,
            type => 'image/svg+xml',
        );
        my $data = join('', @data);
        my $output = qx(echo "$data" | qrencode -t svg);
        print $output;
    } elsif ( $args{format} eq 'qrcode_png' ) {
        print_header( %headers,
            type => 'image/png',
        );
        my $data = join('', @data);
        my $output = qx(echo "$data" | qrencode -t PNG -o -);
        print $output;
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
            version => get_service('config')->id( '_shm' )->get_data->{'version'},
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
    $user->dbh->disconnect();
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

exit 0;
