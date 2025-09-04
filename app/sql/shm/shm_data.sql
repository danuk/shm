BEGIN;

INSERT INTO `users` VALUES
(1,0,'admin','0df78fa86a30eca0a918fdd21a94e238133ce7ab',0,NOW(),NULL,0,0,0.00,NULL,NULL,0,1,0,'Admin',0,0.00,NULL,NULL,NULL,NULL)
;

INSERT INTO `servers_groups` VALUES
(default,'LOCAL','local','random',NULL),
(default,'Email уведомления','mail','random',NULL),
(default,'Telegram уведомления','telegram','random',NULL),
(default,'Linux servers','ssh','random',NULL)
;

INSERT INTO `services` VALUES
(default,'Тестовая услуга',0.00,1.00,'test','[]',NULL,0,NULL,NULL,1,0,NULL,0,NULL,0,0)
;

INSERT INTO `events` VALUES
(default,'UserService','User password reset','user_password_reset',1,'{\"category\": \"%\", \"template_id\": \"user_password_reset\"}')
;

INSERT INTO `templates` VALUES
('forecast','Уважаемый {{ user.full_name }}\n\nУведомляем Вас о сроках действия услуг:\n\n{{ FOR item IN user.pays.forecast.items }}\n- Услуга: {{ item.name }}\n  Стоимость: {{ item.total }} руб.\n  {{ IF item.expire }}\n  Истекает: {{ item.expire }}\n  {{ END }}\n{{ END }}\n\n{{ IF user.pays.forecast.dept }}\nПогашение задолженности: {{ user.pays.forecast.dept }} руб.\n{{ END }}\n\nИтого к оплате: {{ user.pays.forecast.total }} руб.\n\nУслуги, которые не будут оплачены до срока их истечения, будут приостановлены.\n\nПодробную информацию по Вашим услугам Вы можете посмотреть в вашем личном кабинете: {{ config.api.url }}\n\nЭто письмо сформировано автоматически. Если оно попало к Вам по ошибке,\nпожалуйста, сообщите об этом нам: {{ config.mail.from }}',NULL),
('user_password_reset','Уважаемый клиент.\n\nВаш новый пароль: {{ user.set_new_passwd }}\n\nАдрес кабинета: {{ config.cli.url }}','{\"subject\": \"SHM - Восстановление пароля\"}')
;

INSERT INTO `config` VALUES
("_shm", '{"version":"0.0.3"}'),
('billing','{"type": "Simpler", "partner": {"income_percent": 0}}'),
("company", '{"name":"My Company LTD"}'),
("telegram", '{"token":""}'),
("api",     '{"url":"https://bill.domain.ru"}'),
("cli",     '{"url":"https://bill.domain.ru"}'),
("pay_systems",'{"manual":{"name":"Платеж","show_for_client":false},"yoomoney":{"name":"ЮMoney","account":"000000000000000","secret":"","template_id":"yoomoney_template","show_for_client":true}}'),
("mail",    '{"from":"mail@domain.ru"}')
;

INSERT INTO `spool` (id,status,user_id,event) VALUES
(default,'NEW',1,'{"title":"prolongate services","kind":"Jobs","method":"job_prolongate","period":"600"}'),
(default,'PAUSED',1,'{"title":"cleanup services","kind":"Jobs","method":"job_cleanup","period":"86400","settings":{"days":10}}'),
(default,'PAUSED',1,'{"title":"send forecasts","kind":"Jobs","method":"job_make_forecasts","period":"86400"}')
;

COMMIT;

