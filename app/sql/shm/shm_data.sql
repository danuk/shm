BEGIN;

INSERT INTO `users` VALUES
(1,0,'admin','0df78fa86a30eca0a918fdd21a94e238133ce7ab',0,NOW(),NULL,0,0,0,0.00,NULL,NULL,0,0,1,0,'Admin',0,0.00,NULL,NULL,NULL);

INSERT INTO `servers_groups` VALUES
(1,'Основная','random',NULL);

INSERT INTO `templates` VALUES (1,'web_tariff_create','Создание тарифа хостинга','Здравствуйте {{ user.full_name }}\n\nВы зарегистрировали новую услугу: {{ us.service.name }}\n\nДата истечения услуги: {{ us.expired }}\n\nСтоимость услуги: {{ us.service.cost }} руб.\n\nХостинг сайтов:\nХост: {{ child(\'web\').server.settings.host_name }}\nЛогин: {{ child(\'web\').settings.login }}\nПароль: {{ child(\'web\').settings.password }}\n\nЖелаем успехов.',NULL);

INSERT INTO `config` VALUES
(1,'company_name','My Company LTD'),
(2,'shm_url','http://admin.local'),
(3,'mail_from','mail@domain.ru');

COMMIT;
