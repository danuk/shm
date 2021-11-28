BEGIN;

INSERT INTO `users` VALUES
(1,0,'admin','0df78fa86a30eca0a918fdd21a94e238133ce7ab',0,NOW(),NULL,0,0,0,0.00,NULL,NULL,0,0,1,0,'Admin',0,0.00,NULL,NULL,NULL);

INSERT INTO `servers_groups` VALUES
(1,'Основная','ssh','random',NULL);

INSERT INTO `templates` VALUES
(1,'web_tariff_create','Создание тарифа хостинга','Здравствуйте {{ user.full_name }}\n\nВы зарегистрировали новую услугу: {{ us.service.name }}\n\nДата истечения услуги: {{ us.expired }}\n\nСтоимость услуги: {{ us.service.cost }} руб.\n\nХостинг сайтов:\nХост: {{ child(\'web\').server.settings.host_name }}\nЛогин: {{ child(\'web\').settings.login }}\nПароль: {{ child(\'web\').settings.password }}\n\nЖелаем успехов.',NULL),
(2,'yoomoney_template','Код платежной формы ЮMoney','<iframe src=\"https://money.yoomoney.ru/quickpay/shop-widget?writer=seller&targets=%D0%9E%D0%BF%D0%BB%D0%B0%D1%82%D0%B0%20%D0%BF%D0%BE%20%D0%B4%D0%BE%D0%B3%D0%BE%D0%B2%D0%BE%D1%80%D1%83%20{{ user.id }}&targets-hint=&default-sum=100&label={{ user.id }}&button-text=12&payment-type-choice=on&hint=&successURL=&quickpay=shop&account={{ config.pay_systems.yoomoney.account }}\" width=\"100%\" height=\"198\" frameborder=\"0\" allowtransparency=\"true\" scrolling=\"no\"></iframe>',NULL)
;

INSERT INTO `config` VALUES
("_shm", '{"version":"0.0.3"}'),
("_billing",'{"type":"Simpler"}'),
("company", '{"name":"My Company LTD"}'),
("api",     '{"url":"http://shm.local"}'),
("pay_systems",'{"manual":{"name":"Платеж","show_for_client":false},"yoomoney":{"name":"ЮMoney","account":"000000000000000","secret":"","template_id":2,"show_for_client":true}}'),
("mail",    '{"from":"mail@domain.ru"}');

INSERT INTO `spool` (id,status,user_id,event) VALUES
(default,'PAUSED',1,'{"title":"prolongate services","kind":"Jobs","method":"job_prolongate","period":"60"}'),
(default,'PAUSED',1,'{"title":"send forecasts","kind":"Jobs","method":"job_make_forecasts","period":"86400","settings":{"server_id":25,"template_id": 3}}')
;

INSERT INTO `pay_systems` (id,name) VALUES
(1,'Платеж');

COMMIT;
