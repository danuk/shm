BEGIN;

INSERT INTO `users` VALUES
(1,0,'admin','0df78fa86a30eca0a918fdd21a94e238133ce7ab',0,NOW(),NULL,0,0,0,0.00,NULL,NULL,0,0,1,0,'Admin',0,0.00,NULL,NULL,NULL);

INSERT INTO `servers_groups` VALUES
(1,'Основная','ssh','random',NULL),
(2,'VPN','ssh','random',NULL);

INSERT INTO `events` VALUES
(1,'UserService','vpn create','create',2,'{\"category\": \"vpn\"}'),
(2,'UserService','vpn remove','remove',2,'{\"category\": \"vpn\"}'),
(3,'UserService','vpn block','block',2,'{\"category\": \"vpn\"}'),
(4,'UserService','vpn activate','activate',2,'{\"category\": \"vpn\"}');

INSERT INTO `services` VALUES
(1,'VPN',0.00,1.00,'vpn','[]',NULL,0,NULL,NULL,1,0,NULL,0,NULL);

INSERT INTO `templates` VALUES
('web_tariff_create','Здравствуйте {{ user.full_name }}\n\nВы зарегистрировали новую услугу: {{ us.service.name }}\n\nДата истечения услуги: {{ us.expire }}\n\nСтоимость услуги: {{ us.service.cost }} руб.\n\nХостинг сайтов:\nХост: {{ child(\'web\').server.settings.host_name }}\nЛогин: {{ child(\'web\').settings.login }}\nПароль: {{ child(\'web\').settings.password }}\n\nЖелаем успехов.',NULL),
('forecast','Уважаемый {{ user.full_name }}\n\nУведомляем Вас о сроках действия услуг:\n\n{{ FOR item IN user.pays.forecast.items }}\n- Услуга: {{ item.name }}\n  Стоимость: {{ item.total }} руб.\n  Истекает: {{ item.expire }}\n{{ END }}\n\n{{ IF user.pays.forecast.dept }}\nПогашение задолженности: {{ user.pays.forecast.dept }} руб.\n{{ END }}\n\nИтого к оплате: {{ user.pays.forecast.total }} руб.\n\nУслуги, которые не будут оплачены до срока их истечения, будут приостановлены.\n\nПодробную информацию по Вашим услугам Вы можете посмотреть в вашем личном кабинете: {{ config.api.url }}\n\nЭто письмо сформировано автоматически. Если оно попало к Вам по ошибке,\nпожалуйста, сообщите об этом нам: {{ config.mail.from }}',NULL),
('user_password_reset','Уважаемый клиент.\n\nВаш новый пароль: {{ task.settings.new_password }}','{\"subject\": \"SHM - Восстановление пароля\"}'),
('bash_script_example','#!/bin/bash\n\nset -v\n\nUSER_ID=\"{{ user.id }}\"\nUSI=\"{{ us.id }}\"\nEVENT=\"{{ task.event.name }}\"\nSESSION_ID=\"{{ user.gen_session.id }}\"',NULL),
('wg_manager','#!/bin/bash\n\nset -e\n\nEVENT=\"{{ event_name }}\"\nWG_MANAGER=\"/etc/wireguard/wg-manager.sh\"\nSESSION_ID=\"{{ user.gen_session.id }}\"\n\n# We need the --fail-with-body option for curl.\n# It has been added since curl 7.76.0, but almost all Linux distributions do not support it yet.\n# If your distribution has an older version of curl, you can use it (just comment CURL_REPO)\nCURL_REPO=\"https://github.com/moparisthebest/static-curl/releases/download/v7.86.0/curl-amd64\"\nCURL=\"/opt/curl/curl-amd64\"\n#CURL=\"curl\"\n\necho \"EVENT=$EVENT\"\n\ncase $EVENT in\n    INIT)\n        SERVER_HOST=\"{{ server.settings.host_name }}\"\n        SERVER_INTERFACE=\"{{ server.settings.host_interface }}\"\n        if [ -z $SERVER_HOST ]; then\n            echo \"ERROR: set variable \'host_name\' to server settings\"\n            exit 1\n        fi\n\n        apt update\n        apt install -y \\\n            iproute2 \\\n            iptables \\\n            wireguard \\\n            wireguard-tools \\\n            qrencode \\\n            wget\n\n        if [[ $CURL_REPO && ! -f $CURL ]]; then\n            mkdir -p /opt/curl\n            cd /opt/curl\n            wget $CURL_REPO\n            chmod 755 $CURL\n        fi\n\n        cd /etc/wireguard\n        $CURL -s --fail-with-body https://danuk.github.io/wg-manager/wg-manager.sh > $WG_MANAGER\n        chmod 700 $WG_MANAGER\n        if [ $SERVER_INTERFACE ]; then\n            $WG_MANAGER -i -s $SERVER_HOST -I $SERVER_INTERFACE\n        else\n            $WG_MANAGER -i -s $SERVER_HOST\n        fi\n        ;;\n    CREATE)\n        USER_CFG=$($WG_MANAGER -u \"{{ us.id }}\" -c -p)\n\n        $CURL -s --fail-with-body -XPUT \\\n            -H \"session-id: $SESSION_ID\" \\\n            -H \"Content-Type: text/plain\" \\\n            {{ config.api.url }}/shm/v1/storage/manage/vpn{{ us.id }} \\\n            --data-binary \"$USER_CFG\"\n        echo \"done\"\n        ;;\n    ACTIVATE)\n        $WG_MANAGER -u \"{{ us.id }}\" -U\n        echo \"done\"\n        ;;\n    BLOCK)\n        $WG_MANAGER -u \"{{ us.id }}\" -L\n        echo \"done\"\n        ;;\n    REMOVE)\n        $WG_MANAGER -u \"{{ us.id }}\" -d\n        $CURL -s --fail-with-body -XDELETE \\\n            -H \"session-id: $SESSION_ID\" \\\n            {{ config.api.url }}/shm/v1/storage/manage/vpn{{ us.id }}\n        echo \"done\"\n        ;;\n    *)\n        echo \"Unknown event: $EVENT. Exit.\"\n        exit 0\n        ;;\nesac\n\n\n',NULL),
('yoomoney_template','<iframe src=\"https://yoomoney.ru/quickpay/shop-widget?writer=seller&targets=%D0%9E%D0%BF%D0%BB%D0%B0%D1%82%D0%B0%20%D0%BF%D0%BE%20%D0%B4%D0%BE%D0%B3%D0%BE%D0%B2%D0%BE%D1%80%D1%83%20{{ user.id }}&targets-hint=&default-sum=100&label={{ user.id }}&button-text=12&payment-type-choice=on&hint=&successURL=&quickpay=shop&account={{ config.pay_systems.yoomoney.account }}\" width=\"100%\" height=\"198\" frameborder=\"0\" allowtransparency=\"true\" scrolling=\"no\"></iframe>',NULL)
;

INSERT INTO `config` VALUES
("_shm", '{"version":"0.0.3"}'),
("_billing",'{"type":"Simpler"}'),
("company", '{"name":"My Company LTD"}'),
("api",     '{"url":"http://127.0.0.1:8081"}'),
("cli",     '{"url":"http://127.0.0.1:8082"}'),
("pay_systems",'{"manual":{"name":"Платеж","show_for_client":false},"yoomoney":{"name":"ЮMoney","account":"000000000000000","secret":"","template_id":"yoomoney_template","show_for_client":true}}'),
("mail",    '{"from":"mail@domain.ru"}');

INSERT INTO `spool` (id,status,user_id,event) VALUES
(default,'PAUSED',1,'{"title":"prolongate services","kind":"Jobs","method":"job_prolongate","period":"60"}'),
(default,'PAUSED',1,'{"title":"send forecasts","kind":"Jobs","method":"job_make_forecasts","period":"86400","settings":{"server_id":25,"template_id": "forecast"}}')
;

COMMIT;

