BEGIN;

INSERT INTO `acts` VALUES
(default,40092,'2015-01-31 23:59:59',NULL),
(default,40092,'2015-02-28 23:59:59',NULL),
(default,40092,'2015-03-31 23:59:59',NULL),
(default,40092,'2015-04-30 23:59:59',NULL),
(default,40092,'2015-05-31 23:59:59',NULL),
(default,40092,'2015-06-30 23:59:59',NULL);

INSERT INTO `acts_data` VALUES
(default,195,40092,16,19,2662,455.00,'19# Продление домена в зоне .NET: ipcalc.net','2015-10-12 00:00:01','2016-10-12 00:00:00'),
(default,435,40092,11,2946,3518,590.00,'2946# Регистрация домена в зоне .RU: umci.ru','2016-07-29 12:36:06','2017-07-29 12:36:05');

INSERT INTO `apps` VALUES
(default,40092,101,'phpBB',270,'{\"db_name\":\"phpBB\",\"password\":\"OOgWCha2\",\"db_user\":\"phpBB\",\"domain\":\"work.biit.ru\",\"domain_dir\":\"utf8\",\"login\":\"Admin\",\"dir\":\"\"}'),
(default,40092,101,'WordPress',7,'{\"db_name\":\"WordPress\",\"db_user\":\"WordPress\",\"domain\":\"ipcalc.net\",\"domain_dir\":\"ipcalc.net\",\"dir\":\"wp\"}');

INSERT INTO `discounts` VALUES
(default,'1 месяц',1,0,NULL),
(default,'3 месяца',3,10,NULL),
(default,'6 месяцев',6,15,NULL),
(default,'1 год',12,20,NULL),
(default,'2 года',24,30,NULL),
(default,'3 года',36,40,NULL);

INSERT INTO `dns_services` VALUES
(default,12,'ri','A',0,'195.91.217.35',0),
(default,12,'on','A',0,'95.84.154.134',0),
(default,12,'ns1','A',0,'195.91.217.35',0),
(default,12,'ns1','A',0,'95.84.154.134',0),
(default,12,'ns2','A',0,'185.22.232.59',0),
(default,12,'srv0','A',0,'195.91.217.35',0),
(default,12,'*.srv0','A',0,'195.91.217.35',0),
(default,12,'pm','A',0,'185.22.232.59',0),
(default,12,'bill','A',0,'185.22.232.59',0),
(default,12,'binder1','A',0,'193.26.217.194',0),
(default,12,'binder2','A',0,'185.22.232.59',0),
(default,12,'bill','A',0,'193.26.217.194',0),
(default,11,'ftp','A',0,'195.91.217.35',0),
(default,12,'pm','A',0,'193.26.217.194',0),
(default,11,'bill','A',0,'95.84.154.134',0),
(default,31,'ns1','A',0,'95.84.154.134',0),
(default,31,'ns2','A',0,'185.22.232.59',0),
(default,12,'mail','A',0,'193.26.217.194',0),
(default,67,'test','A',0,'1.2.3.4',0),
(default,76,'@','MX',10,'aspmx.l.google.com.',0),
(default,11,'binder3','A',0,'188.227.18.207',0),
(default,151,'.','A',0,'188.227.18.207',0),
(default,151,'.','A',0,'185.22.232.59',0),
(default,204,'@','A',0,'185.22.232.59',0),
(default,177,'www','TXT',0,'yandex-verification: 5ac84e25f60b3c63',0),
(default,207,'@','MX',4,'mx.yandex.net.',0),
(default,193,'@','MX',4,'mx.yandex.net.',0),
(default,283,'@','MX',10,'emx.mail.ru.',0),
(default,283,'@','TXT',0,'v=spf1 redirect=_spf.mail.ru',0),
(default,283,'mailru._domainkey','TXT',0,'v=dkim1; k=rsa; p=migfma0gcsqgsib3dqebaquaa4gnadcbiqkbgqdxoswyykb8uja5yybxp1jka9ws3akdzbqkhmv9ersmw7ye+ni4ea0+qugo5qenmskbbpykjyxhyz70zud2cqhoi6djigdse1uigig3b7mdkgn5arj6nszrfhc5tt6qheqse2jwj6z0sds5rgtvpzfplpkskjoj1nnx+sxlab2uiqidaqab',0),
(default,12,'vps','CNAME',0,'on',0),
(default,25,'@','TXT',0,'v=spf1 include:spf.unisender.com ~all',0),
(default,25,'@','TXT',0,'spf2.0/mfrom,pra include:senderid.unisender.com ~all',0),
(default,25,'_domainkey','TXT',0,'o=~',0),
(default,25,'us._domainkey','TXT',0,'k=rsa; p=migfma0gcsqgsib3dqebaquaa4gnadcbiqkbgqdxi30oc9sqaeiznnfx894nw4regja+kgqtavfs1mosxdwxlrtmdqf9daa3smfuiuolpxzv8fick0mskars8kp5orgdhfm9zo8ugikffvgcuufvigdhzntu+mbozd7bxf2k7ag9ujao1y08iz9u9unfr971u1jrr+wnl5pnxj+r4qidaqab',0),
(default,299,'test','A',0,'1.1.1.1',0),
(default,299,'test1','A',0,'1.2.3.4',0),
(default,299,'dfsdf','A',0,'1.2.1.1',0),
(default,308,'@','A',0,'37.46.134.76',0),
(default,308,'*','A',0,'37.46.134.76',0),
(default,207,'travel','CNAME',0,'whitelabel.travelpayouts.com.',0),
(default,207,'tours','CNAME',0,'qui-quo.ru.',0),
(default,11,'mail','CNAME',0,'www',0),
(default,181,'radio','A',0,'82.146.43.227',0),
(default,284,'@','MX',1,'aspmx.l.google.com.',0),
(default,284,'@','MX',5,'alt1.aspmx.l.google.com.',0),
(default,284,'@','MX',5,'alt2.aspmx.l.google.com.',0),
(default,284,'@','MX',10,'alt3.aspmx.l.google.com.',0),
(default,284,'@','MX',10,'alt4.aspmx.l.google.com.',0),
(default,157,'www','A',0,'185.22.232.59',0),
(default,157,'@','A',0,'185.22.232.59',0),
(default,327,'@','A',0,'95.85.10.40',0),
(default,327,'www','A',0,'95.85.10.40',0),
(default,326,'@','A',0,'95.85.10.40',0),
(default,326,'www','A',0,'95.85.10.40',0),
(default,325,'@','A',0,'95.85.10.40',0),
(default,325,'www','A',0,'95.85.10.40',0),
(default,25,'pay','A',0,'185.31.161.56',0),
(default,328,'@','A',0,'95.85.10.40',0),
(default,328,'www','A',0,'95.85.10.40',0);

INSERT INTO `domains` VALUES
(6,40092,'danuk.ru','2017-01-01 00:00:00',0,NULL,NULL,16),
(7,40092,'ipcalc.net','2017-01-02 00:00:00',0,NULL,NULL,19),
(33,40094,'xims.ru','2017-01-03 00:00:00',0,NULL,NULL,210),
(306,40092,'admin.danuk.ru','2017-01-04 00:00:00',0,6,NULL,16),
(100,40094,'xiwe.ru','2017-01-05 00:00:00',0,NULL,NULL,836),
(270,40092,'work.biit.ru','2017-01-06 00:00:00',0,11,NULL,59),
(142,40094,'moto-season.ru','2017-01-07 00:00:00',0,NULL,NULL,1326),
(144,40094,'evileye.ru','2017-01-08 00:00:00',0,NULL,NULL,1339),
(305,40092,'cli.danuk.ru','2017-01-09 00:00:00',0,6,NULL,16),
(308,40092,'umci.ru','2017-01-10 00:00:00',1,NULL,NULL,2949),
(150,40094,'rctrl.ru','2017-01-11 00:00:00',0,NULL,NULL,1380),
(151,40094,'r-ctrl.ru','2017-01-12 00:00:00',0,NULL,NULL,1383),
(304,40092,'shm.danuk.ru','2017-01-13 00:00:00',0,6,NULL,16),
(208,40094,'gpb.xims.ru','2017-01-14 00:00:00',0,33,NULL,210),
(210,40094,'gpb1.xims.ru','2017-01-15 00:00:00',0,33,NULL,210),
(211,40094,'gpb2.xims.ru','2017-01-16 00:00:00',0,33,NULL,210);

INSERT INTO `domains_services` VALUES
(default,6,101,'2017-09-23 23:54:04'),
(default,7,101,'2017-09-23 23:54:04'),
(default,33,1872,'2017-09-23 23:54:04'),
(default,306,101,'2017-09-23 23:54:04'),
(default,100,1872,'2017-09-23 23:54:04'),
(default,270,101,'2017-09-23 23:54:04'),
(default,142,1872,'2017-09-23 23:54:04'),
(default,144,1872,'2017-09-23 23:54:04'),
(default,305,101,'2017-09-23 23:54:04'),
(default,150,1872,'2017-09-23 23:54:04'),
(default,304,101,'2017-09-23 23:54:04'),
(default,208,1872,'2017-09-23 23:54:04'),
(default,210,1872,'2017-09-23 23:54:04'),
(default,211,1872,'2017-09-23 23:54:04'),
(default,6,100,'2017-09-23 23:54:23'),
(default,7,100,'2017-09-23 23:54:23'),
(default,144,1871,'2017-09-23 23:54:23'),
(default,6,16,'2017-09-23 00:00:01'),
(default,6,2950,'2017-11-05 17:40:30'),
(default,6,2951,'2017-11-05 17:40:33'),
(default,150,1871,'2017-09-23 23:54:23');

INSERT INTO `invoices` VALUES
(default,1414222040,40092,100.00,NULL),
(default,1414228287,40092,1000.00,NULL),
(default,1481294791,40092,578.20,NULL);

INSERT INTO `pays_history` VALUES
(default,40092,1,455.00,'2014-10-02 14:05:39',''),
(default,40092,1,455.00,'2016-01-04 20:33:35','');

INSERT INTO `servers` VALUES
(1,1,'test server (local)','ssh','ssm@127.0.0.1','127.0.0.1',100,0,0,1,'{\"cmd\": \"test create\", \"key_id\": 1, \"host_name\": \"host1.domain.ru\"}'),
(25,5,'mail-1','mail','127.0.0.1:25',NULL,100,0,0,1,NULL);

INSERT INTO `servers_groups` VALUES
(1,'Сервера Web хостинга','ssh','random',NULL),
(2,'Сервера MySQL хостинга','ssh','random',NULL),
(3,'Сервера Mail хостинга','ssh','random',NULL),
(4,'Сервера DNS','ssh','random',NULL),
(5,'Сервис email уведомлений','mail','random',NULL);

INSERT INTO `services` VALUES
(1,'Тариф \"Почтовый\" (${QUOTA} мб)',75,0,'web_tariff_lock',NULL,NULL,NULL,NULL,1,NULL,'Тарифный план включает в себя набор услуг. Все услуги, включенные в тарифный план, полностью зависят от статуса тарифа.',NULL,NULL),
(2,'Тариф MIN (${QUOTA} мб)',100,0,'web_tariff',NULL,NULL,NULL,NULL,1,NULL,'Тарифный план включает в себя набор услуг. Все услуги, включенные в тарифный план, полностью зависят от статуса тарифа.',NULL,NULL),
(4,'Тариф MAX (${QUOTA} мб)',200,0,'web_tariff',NULL,NULL,NULL,NULL,1,NULL,'Тарифный план включает в себя набор услуг. Все услуги, включенные в тарифный план, полностью зависят от статуса тарифа.',NULL,NULL),
(5,'Web хостинг (${QUOTA} мб)',100,1,'web',NULL,NULL,NULL,1,NULL,NULL,'Web хостинг - услуга, позволяющая размещать ваш WEB сайт на сервере хостинга. Вы можете размещать несколько сайтов на одной площадке.',NULL,NULL),
(8,'Почта (${QUOTA} мб)',100,1,'mail',NULL,NULL,NULL,1,NULL,NULL,'Почта - услуга позволяет размещать почту на сервере для своих доменов',NULL,NULL),
(11,'Регистрация домена в зоне .RU: ${DOMAIN}',590,12,'domain',12,NULL,NULL,NULL,1,1,'Регистрация домена осуществляется регистратором доменных имен.',NULL,NULL),
(12,'Продление домена в зоне .RU: ${DOMAIN}',890,12,'domain_prolong',NULL,NULL,NULL,NULL,1,1,NULL,NULL,NULL),
(29,'База данных MySQL (${quota} мб)',0,1,'mysql',NULL,NULL,NULL,NULL,NULL,NULL,'услуга позволяет использовать базу данных для своих сайтов.',NULL,NULL),
(30,'Первичный DNS: ${NS}',0,1,'dns',NULL,1,NULL,NULL,NULL,NULL,NULL,NULL,'{"ns":"ns1.biit.ru"}'),
(31,'Вторичный DNS: ${NS}',0,1,'dns',NULL,1,NULL,NULL,NULL,NULL,NULL,NULL,'{"ns":"ns2.biit.ru"}'),
(50,'Домен: ${DOMAIN}',0,0,'domain_add',NULL,NULL,NULL,1,NULL,NULL,NULL,NULL,NULL),
(63,'Трансфер домена: ${DOMAIN}',0,12,'transfer',NULL,NULL,1,NULL,1,1,'Домен зарегистрирован в системе как &quot;Трансфер&quot;. Такие домены владелец продляет самостоятельно.',NULL,NULL),
(110,'Тариф X-MAX (${QUOTA} мб)',300,1,'web_tariff',NULL,NULL,NULL,NULL,1,NULL,'Тарифный план включает в себя набор услуг. Все услуги, включенные в тарифный план, полностью зависят от статуса тарифа.',NULL,NULL),
(111,'Web хостинг (${QUOTA} мб)',0,1,'web',NULL,NULL,NULL,1,NULL,NULL,'Web хостинг - услуга, позволяющая размещать ваш WEB сайт на сервере хостинга. Вы можете размещать несколько сайтов на одной площадке.',NULL,NULL),
(112,'Почта (${QUOTA} мб)',0,1,'mail',NULL,NULL,NULL,1,NULL,NULL,'Почта - услуга позволяет размещать почту на сервере для своих доменов',NULL,NULL);

INSERT INTO `events` VALUES
(default,'UserService','Chanor web account','passwd',NULL,'{"category":"web","cmd":"www passwd w_{{us.parent}}"}'),
(default,'UserService','Notification of change password for web account','passwd',NULL,'{"category":"web","template":"web_pass_change","transport":"mail"}'),
(default,'UserService','Add domain to web account','create',1,'{"category":"domain_add","cmd":"www create w_{{us.parent}} {{us.settings.domain}},www.{{us.settings.domain}} {{parent.settings.max_quota}}"}'),
(default,'UserService','Remove domain from web account','delete',1,'{"category":"domain_add","cmd":"www delete w_{{us.parent}} {{us.settings.domain}},www.{{us.settings.domain}}"}'),
(default,'UserService','Create mysql','create',1,'{"category":"mysql","cmd":"mysql create -a b_{{id}} -b {{us.settings.db.0.name}} -u {{us.settings.db.0.login}} -p {{us.settings.db.0.password}}"}'),
(default,'UserService','Erase mysql','remove',NULL,'{"category":"mysql","cmd":"mysql erase b_{{id}}"}'),
(default,'UserService','Block mysql','block',NULL,'{"category":"mysql","cmd":"mysql block b_{{id}}"}'),
(default,'UserService','Activate mysql','activate',NULL,'{"category":"mysql","cmd":"mysql unblock b_{{id}}"}'),
(default,'UserService','Create dns','create',1,'{"category":"dns","cmd":"dns update","stdin":"{{payload}}"}'),
(default,'UserService','Erase dns','remove',NULL,'{"category":"dns","cmd":"dns erase {{us.domain}}"}'),
(default,'UserService','Update dns','update',NULL,'{"category":"dns","cmd":"dns update","stdin":"{{payload}}"}'),
(default,'UserService','Test Docker command','create',1,'{"cmd":"ansible-playbook --extra-vars \'{{US}}\'","transport":"docker"}');

INSERT INTO `subservices` VALUES
(default,1,8),
(default,2,8),
(default,2,5),
(default,2,29),
(default,4,5),
(default,4,8),
(default,4,29),
(default,11,30),
(default,11,31),
(default,110,112),
(default,110,111),
(default,110,29),
(default,63,30),
(default,63,31);

INSERT INTO `user_services` VALUES (16,40092,63,1,3583,'2014-10-02 13:47:30','2017-09-22 14:51:26','ACTIVE',0,NULL,'{\"ns1\": \"ns1.viphost.ru\", \"ns2\": \"ns2.viphost.ru\", \"domain\": \"danuk.ru\", \"nic_id\": \"184677/NIC-D\\n\", \"punycode\": \"\", \"domain_id\": \"6\"}'),
(17,40092,30,1,NULL,'2014-10-02 13:47:30',NULL,'ACTIVE',0,16,'{\"ns\": \"ns1.viphost.ru\", \"domain_id\": \"6\", \"server_id\": 1}'),
(18,40092,31,1,NULL,'2014-10-02 13:47:30',NULL,'ACTIVE',0,16,'{\"ns\": \"ns2.viphost.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"6\", \"server_id\": 1}'),
(19,40092,63,1,3670,'2014-10-02 14:04:19','2017-01-11 23:59:59','ACTIVE',0,NULL,'{\"ns1\": \"ns1.viphost.ru\", \"ns2\": \"ns2.viphost.ru\", \"domain\": \"ipcalc.net\", \"nic_id\": \"184677/NIC-D\\n\", \"nic_hdl\": \"U35A35Y-RU\\n\", \"punycode\": \"\", \"domain_id\": \"7\", \"max_quota\": \"4000\"}'),
(20,40092,30,1,NULL,'2014-10-02 14:04:19',NULL,'ACTIVE',0,19,'{\"ns\": \"ns1.viphost.ru\", \"domain_id\": \"7\", \"server_id\": 1}'),
(21,40092,31,1,NULL,'2014-10-02 14:04:19',NULL,'ACTIVE',0,19,'{\"ns\": \"ns2.viphost.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"7\", \"server_id\": 1}'),
(99,40092,110,1,3691,'2014-10-07 12:56:09','2017-01-31 23:59:50','ACTIVE',0,NULL,'{\"quota\": \"10000\"}'),
(100,40092,112,1,NULL,'2014-10-07 12:56:09',NULL,'ACTIVE',0,99,'{\"quota\": \"46\", \"domain_id\": \"7\", \"max_quota\": \"9867\", \"server_id\": 1, \"max_domains\": \"3\"}'),
(101,40092,111,1,NULL,'2014-10-07 12:56:09',NULL,'ACTIVE',0,99,'{\"group\": \"limits0\", \"login\": \"w_101\", \"quota\": \"3391\", \"password\": \"enos1aer\", \"domain_id\": \"306\", \"max_quota\": \"9821\", \"server_id\": 1, \"binder_grp\": \"4\", \"max_domains\": \"3\"}'),
(102,40092,29,1,NULL,'2014-10-07 12:56:09',NULL,'ACTIVE',0,99,'{\"port\": \"4011\", \"login\": \"w_102\", \"quota\": \"133\", \"account\": \"b_102\", \"charset\": \"windows-1251\", \"db_name\": \"db1\", \"db_count\": \"0\", \"password\": \"D4EfbNEB\", \"max_quota\": \"10000\", \"server_id\": 1, \"rootpassword\": \"oobi6aay\"}'),
(123,40092,50,1,NULL,'2014-10-23 13:41:35',NULL,'ACTIVE',0,100,NULL),
(210,40094,63,1,90,'2015-01-26 14:12:40',NULL,'ACTIVE',0,NULL,'{\"domain\": \"xims.ru\", \"punycode\": \"\", \"domain_id\": \"33\"}'),
(211,40094,30,1,NULL,'2015-01-26 14:12:40',NULL,'ACTIVE',0,210,'{\"ns\": \"ns1.viphost.ru\", \"domain_id\": \"33\", \"server_id\": 1}'),
(212,40094,31,1,NULL,'2015-01-26 14:12:40',NULL,'ACTIVE',0,210,'{\"ns\": \"ns2.viphost.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"33\", \"server_id\": 1}'),
(242,40092,50,1,NULL,'2015-01-30 11:32:01',NULL,'ACTIVE',0,100,NULL),
(665,40092,50,1,NULL,'2015-09-01 13:36:25',NULL,'ACTIVE',0,101,'{\"domain\": \"danuk.ru\", \"domain_id\": \"6\"}'),
(836,40094,63,1,2528,'2015-09-16 21:57:22',NULL,'ACTIVE',0,NULL,'{\"domain\": \"xiwe.ru\", \"nic_id\": null, \"punycode\": \"\", \"domain_id\": \"100\"}'),
(837,40094,30,1,NULL,'2015-09-16 21:57:22',NULL,'ACTIVE',0,836,'{\"ns\": \"ns1.biit.ru\", \"domain_id\": \"100\", \"server_id\": 1}'),
(838,40094,31,1,NULL,'2015-09-16 21:57:22',NULL,'ACTIVE',0,836,'{\"ns\": \"ns2.biit.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"100\", \"server_id\": 1}'),
(1326,40094,63,1,2684,'2015-10-16 14:35:06',NULL,'ACTIVE',0,NULL,'{\"domain\": \"moto-season.ru\", \"nic_id\": null, \"punycode\": \"\", \"domain_id\": \"142\"}'),
(1327,40094,30,1,NULL,'2015-10-16 14:35:06',NULL,'ACTIVE',0,1326,'{\"ns\": \"ns1.biit.ru\", \"domain_id\": \"142\", \"server_id\": 1}'),
(1328,40094,31,1,NULL,'2015-10-16 14:35:06',NULL,'ACTIVE',0,1326,'{\"ns\": \"ns2.biit.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"142\", \"server_id\": 1}'),
(1339,40094,63,1,2688,'2015-10-17 11:57:44',NULL,'ACTIVE',0,NULL,'{\"domain\": \"evileye.ru\", \"nic_id\": null, \"punycode\": \"\", \"domain_id\": \"144\"}'),
(1340,40094,30,1,NULL,'2015-10-17 11:57:44',NULL,'ACTIVE',0,1339,'{\"ns\": \"ns1.biit.ru\", \"domain_id\": \"144\", \"server_id\": 1}'),
(1341,40094,31,1,NULL,'2015-10-17 11:57:44',NULL,'ACTIVE',0,1339,'{\"ns\": \"ns2.biit.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"144\", \"server_id\": 1}'),
(1380,40094,63,1,2702,'2015-10-22 14:40:11',NULL,'ACTIVE',0,NULL,'{\"domain\": \"rctrl.ru\", \"nic_id\": null, \"punycode\": \"\", \"domain_id\": \"150\"}'),
(1381,40094,30,1,NULL,'2015-10-22 14:40:11',NULL,'ACTIVE',0,1380,'{\"ns\": \"ns1.biit.ru\", \"domain_id\": \"150\", \"server_id\": 1}'),
(1382,40094,31,1,NULL,'2015-10-22 14:40:11',NULL,'ACTIVE',0,1380,'{\"ns\": \"ns2.biit.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"150\", \"server_id\": 1}'),
(1383,40094,63,1,2703,'2015-10-22 14:40:17',NULL,'ACTIVE',0,NULL,'{\"domain\": \"r-ctrl.ru\", \"nic_id\": null, \"punycode\": \"\", \"domain_id\": \"151\"}'),
(1384,40094,30,1,NULL,'2015-10-22 14:40:17',NULL,'ACTIVE',0,1383,'{\"ns\": \"ns1.biit.ru\", \"domain_id\": \"151\", \"server_id\": 1}'),
(1385,40094,31,1,NULL,'2015-10-22 14:40:17',NULL,'ACTIVE',0,1383,'{\"ns\": \"ns2.biit.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"151\", \"server_id\": 1}'),
(1870,40094,2,1,3690,'2015-11-04 19:45:25','2017-01-31 21:23:29','ACTIVE',0,NULL,'{\"quota\": \"1000\", \"free_tariff\": \"196\"}'),
(1871,40094,8,1,NULL,'2015-11-04 19:45:25',NULL,'ACTIVE',0,1870,'{\"quota\": \"2\", \"domain_id\": \"150\", \"max_quota\": \"995\", \"server_id\": 1}'),
(1872,40094,5,1,NULL,'2015-11-04 19:45:25',NULL,'ACTIVE',0,1870,'{\"group\": \"limits1\", \"login\": \"w_1872\", \"quota\": \"583\", \"password\": \"fi6eepe5\", \"domain_id\": \"210\", \"max_quota\": \"993\", \"server_id\": 1, \"binder_grp\": \"4\", \"max_domains\": \"10\"}'),
(1873,40094,29,1,NULL,'2015-11-04 19:45:25',NULL,'ACTIVE',0,1870,'{\"port\": \"4260\", \"quota\": \"5\", \"account\": \"b_1873\", \"charset\": \"windows-1251\", \"db_name\": \"db1\", \"db_count\": \"0\", \"password\": \"ra5Cm22T\", \"max_quota\": \"1000\", \"server_id\": \"3\", \"rootpassword\": \"hae6eem1\"}'),
(1875,40094,50,1,NULL,'2015-11-04 19:45:25',NULL,'ACTIVE',NULL,1872,'{\"domain\": \"moto-season.ru\", \"directory\": \"moto-season.ru\", \"domain_id\": \"142\"}'),
(1876,40094,50,1,NULL,'2015-11-04 20:56:54',NULL,'ACTIVE',0,1872,'{\"domain\": \"xims.ru\", \"directory\": \"xims.ru\", \"domain_id\": \"33\"}'),
(1877,40094,50,1,NULL,'2015-11-04 20:56:58',NULL,'ACTIVE',0,1872,'{\"domain\": \"xiwe.ru\", \"directory\": \"xiwe.ru\", \"domain_id\": \"100\"}'),
(1878,40094,50,1,NULL,'2015-11-04 20:57:04',NULL,'ACTIVE',0,1872,'{\"domain\": \"evileye.ru\", \"directory\": \"evileye.ru\", \"domain_id\": \"144\"}'),
(1880,40094,50,1,NULL,'2015-11-04 20:57:30',NULL,'ACTIVE',0,1872,'{\"domain\": \"rctrl.ru\", \"directory\": \"rctrl.ru\", \"domain_id\": \"150\"}'),
(1881,40094,50,1,NULL,'2015-11-04 23:36:26',NULL,'ACTIVE',0,1871,'{\"domain\": \"evileye.ru\", \"domain_id\": \"144\"}'),
(1882,40094,50,1,NULL,'2015-11-04 23:36:47',NULL,'ACTIVE',0,1871,'{\"domain\": \"rctrl.ru\", \"domain_id\": \"150\"}'),
(2140,40094,50,1,NULL,'2015-12-22 20:48:52',NULL,'ACTIVE',0,1872,'{\"domain\": \"gpb.xims.ru\", \"directory\": \"gpb.xims.ru\", \"domain_id\": \"208\"}'),
(2150,40094,50,1,NULL,'2015-12-23 11:46:35',NULL,'ACTIVE',0,1872,NULL),
(2151,40094,50,1,NULL,'2015-12-23 15:39:39',NULL,'ACTIVE',0,1872,'{\"domain\": \"gpb1.xims.ru\", \"directory\": \"gpb1.xims.ru\", \"domain_id\": \"210\"}'),
(2801,40094,63,1,3357,'2016-02-15 21:55:29',NULL,'ACTIVE',0,NULL,'{\"domain\": \"keram.ru\", \"nic_id\": null, \"punycode\": \"\", \"domain_id\": \"283\"}'),
(2802,40094,30,1,NULL,'2016-02-15 21:55:29',NULL,'ACTIVE',0,2801,'{\"ns\": \"ns1.biit.ru\", \"domain_id\": \"283\", \"server_id\": 1}'),
(2803,40094,31,1,NULL,'2016-02-15 21:55:29',NULL,'ACTIVE',0,2801,'{\"ns\": \"ns2.biit.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"283\", \"server_id\": 1}'),
(2942,40092,50,1,NULL,'2016-07-22 12:01:24',NULL,'ACTIVE',0,101,'{\"domain\": \"shm.danuk.ru\", \"directory\": \"shm.danuk.ru\", \"domain_id\": \"304\"}'),
(2943,40092,50,1,NULL,'2016-07-23 18:12:26',NULL,'ACTIVE',0,101,'{\"domain\": \"cli.danuk.ru\", \"directory\": \"cli.danuk.ru\", \"domain_id\": \"305\"}'),
(2944,40092,50,1,NULL,'2016-07-24 18:49:14',NULL,'ACTIVE',0,101,'{\"domain\": \"admin.danuk.ru\", \"directory\": \"admin.danuk.ru\", \"domain_id\": \"306\"}'),
(2949,40092,11,1,3519,'2016-07-29 12:39:47','2017-07-29 12:39:46','ACTIVE',12,NULL,'{\"quota\": \"0\", \"domain\": \"umci.ru\", \"nic_id\": \"2628443\", \"punycode\": \"\", \"domain_id\": \"308\", \"max_quota\": \"1000\"}'),
(2950,40092,30,1,NULL,'2016-07-29 12:39:08',NULL,'ACTIVE',0,2949,'{\"ns\": \"ns1.biit.ru\", \"domain_id\": \"308\", \"server_id\": 1}'),
(2951,40092,31,1,NULL,'2016-07-29 12:39:08',NULL,'ACTIVE',0,2949,'{\"ns\": \"ns2.biit.ru\", \"master\": \"185.31.160.56\", \"domain_id\": \"308\", \"server_id\": 1}');
INSERT INTO `users` VALUES
(1,0,'admin','0df78fa86a30eca0a918fdd21a94e238133ce7ab',0,NOW(),NULL,0,0,0,0.00,NULL,NULL,0,0,1,0,'Admin',0,0.00,NULL,NULL,NULL),
(108,0,'','',0,'2014-09-30 14:17:37',NULL,0,0.00,0,0.00,NULL,NULL,0,0,NULL,0,'Платеж',0,0.00,NULL,NULL,NULL),
(40092,0,'danuk','6d1834669427053343724aeed08952b09f72f879',0,'2014-09-30 14:17:37',NULL,0,-21.56,30,100000.00,NULL,NULL,0,0,1,0,'Фирсов Даниил Андреевич',0,100.00,NULL,NULL,NULL),
(40094,0,'xims','1ad777afc152c9eaa13abb53283f8d47e8d453bb',0,'2014-10-02 14:45:43',NULL,0,0.00,30,100.00,NULL,NULL,0,0,NULL,0,'Смолев Михаил Владимирович',0,0.00,NULL,NULL,NULL);

INSERT INTO `withdraw_history` VALUES
(6,40092,'2014-10-02 13:47:30','2014-10-02 13:47:30',NULL,0.00,0,0.00,12,0.00,63,1,16),
(3349,40094,'2016-02-11 11:07:01','2016-02-29 21:33:40','2016-03-31 21:23:33',0.00,0,0.00,1,0.00,2,1,1870),
(3691,40092,'2017-01-01 00:00:01','2016-12-31 23:59:51','2017-01-31 23:59:50',0.00,0,0.00,1,0.00,110,1,99),
(3732,40092,'2017-01-01 00:00:00','2017-01-01 00:00:00','2017-01-01 23:59:59',1004.13,0,0.00,0.01,32.39,4,1,3087),
(3733,40092,'2017-01-01 00:00:00','2017-01-01 00:00:00','2017-01-01 23:59:59',1004.13,0,0.00,0.01,32.39,4,1,3088);

INSERT INTO `zones` VALUES
(1,'ru',1,'whois.ripn.net','No entries found for the selected',11,2,0,'domain_ru','client_ru',0,0,0),
(2,'com',2,'whois.crsnic.net','No match for',13,2,0,'domain_rrp','client_rrp',1,1,0),
(3,'net',3,'whois.crsnic.net','No match for',15,2,0,'domain_rrp','client_rrp',1,1,0),
(4,'org',4,'whois.pir.org','NOT FOUND',17,2,0,'domain_rrp','client_rrp',1,1,0),
(5,'su',5,'whois.ripn.net','No entries found for the selected',19,3,0,'domain_su','client_ru',0,1,0),
(6,'biz',6,'whois.biz','Not found',21,3,0,'domain_rrp','client_rrp',1,0,0),
(7,'info',7,'whois.afilias.net','NOT FOUND',23,3,0,'domain_rrp','client_rrp',1,0,0),
(8,'me',8,'whois.nic.me','NOT FOUND',101,3,0,'domain_epp_me','client_rrp',1,0,0),
(9,'cc',9,'whois.nic.cc','No match for',103,3,0,'domain_epp_cc','client_rrp',1,1,0),
(10,'tv',10,'whois.nic.tv','No match for',105,3,0,'domain_epp_tv','client_rrp',1,1,0),
(11,'name',11,'whois.nic.name','No match',107,3,0,'domain_epp_name','client_rrp',1,1,0),
(12,'РФ',0,'whois.ripn.net','No entries found for the selected source',116,3,0,'domain_rf','domain_rf',0,0,1),
(13,'bz',15,'whois.afilias-grs.info','NOT FOUND',128,3,0,'domain_epp_bz','client_rrp',1,0,0),
(14,'ag',127,'whois.nic.ag','NOT FOUND',138,3,0,'domain_epp_ag','client_rrp',1,0,0),
(15,'hn',17,'whois2.afilias-grs.net','NOT FOUND',130,3,0,'domain_epp_hn','client_rrp',1,0,0),
(16,'lc',18,'whois.nic.lc','NOT FOUND',132,3,0,'domain_epp_lc','client_rrp',1,0,0),
(17,'mn',19,'whois2.afilias-grs.net','NOT FOUND',140,3,0,'domain_epp_mn','client_rrp',1,0,0),
(18,'sc',20,'whois.afilias-grs.info','NOT FOUND',134,3,0,'domain_epp_sc','client_rrp',1,0,0),
(19,'vc',10,'whois.opensrs.net','NOT FOUND',136,3,0,'domain_epp_vc','client_rrp',1,0,0),
(20,'pro',10,'whois.registrypro.pro','NOT FOUND',142,4,0,'domain_epp_pro','client_rrp',1,0,0),
(21,'mobi',13,'whois.dotmobiregistry.net','NOT FOUND',144,3,0,'domain_epp_mobi','client_rrp',1,0,0),
(22,'net.ru',8,'whois.nic.ru','No entries found for',146,3,0,'domain_net_ru','client_ru',0,0,0),
(23,'org.ru',8,'whois.nic.ru','No entries found for',148,3,0,'domain_org_ru','client_ru',0,0,0),
(24,'pp.ru',8,'whois.nic.ru','No entries found for',150,3,0,'domain_pp_ru','client_ru',0,0,0),
(25,'msk.ru',8,'whois.nic.ru','No entries found for',152,3,0,'domain_msk_ru','client_ru',0,0,0),
(26,'msk.su',8,'whois.nic.ru','No entries found for',154,3,0,'domain_msk_su','client_ru',0,0,0),
(27,'spb.ru',8,'whois.nic.ru','No entries found for',156,3,0,'domain_spb_ru','client_ru',0,0,0),
(28,'spb.su',8,'whois.nic.ru','No entries found for',158,3,0,'domain_spb_su','client_ru',0,0,0),
(29,'xxx',110,'whois.nic.xxx','NOT FOUND',175,3,0,'domain_epp_xxx','client_rrp',1,0,0),
(30,'com.ru',8,'whois.nic.ru','No entries found for',198,3,0,'domain_com_ru','client_ru',0,0,0);

INSERT INTO `identities` VALUES (1,'test','-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn\nNhAAAAAwEAAQAAAQEAp790kROYX+oVfnJxF5yyaeFAa0/BLtkDdnBeYo/LmS6WbGx3UyaA\nqb29i8KQcFmEWe6gzNDOM92/lb3gNJbW0TfLI1GHP8AT7A0wYsH9/2K/1woItCjOQMkn6K\nu4XIWOykascPYiPXGiToQkftuzf4eh5u1jPWXu6MpxpLe7bjCjP0BieKoAkILghzO5+olM\n1FjA2IXPT9UMxJr97UHXC0sMz/QJR09bjw0pZ89ZKI6R+bevUzenZgcV1BEp8E1ZvQHYDQ\nvsGC38e7pyhQCIH649V2TuedGdp3aysAOofVN3rKoVeO46GWPUMcJ0rHfeK6JjlK2ApZwS\nYJ+1sYuX3wAAA9BmBrFbZgaxWwAAAAdzc2gtcnNhAAABAQCnv3SRE5hf6hV+cnEXnLJp4U\nBrT8Eu2QN2cF5ij8uZLpZsbHdTJoCpvb2LwpBwWYRZ7qDM0M4z3b+VveA0ltbRN8sjUYc/\nwBPsDTBiwf3/Yr/XCgi0KM5AySfoq7hchY7KRqxw9iI9caJOhCR+27N/h6Hm7WM9Ze7oyn\nGkt7tuMKM/QGJ4qgCQguCHM7n6iUzUWMDYhc9P1QzEmv3tQdcLSwzP9AlHT1uPDSlnz1ko\njpH5t69TN6dmBxXUESnwTVm9AdgNC+wYLfx7unKFAIgfrj1XZO550Z2ndrKwA6h9U3esqh\nV47joZY9QxwnSsd94romOUrYClnBJgn7Wxi5ffAAAAAwEAAQAAAQB69nTUA7EmXcjzr6AG\n1u5RfrRh9Ux+ssU/BI+rYAy2dNf/EmNFqGuYAWX4FN8b/AJwieOFP2pnypytf0niQs+k/W\nkCsriZmor/9YsKWXl+wzwsvUY0CdVm2A1RGM9DwwMwcy3kgAgJUkrPkz3NX+7sBNhBFrIw\nR5AhRISZYbUax4xcBUKEjL7WvWa7YRo4dGcal1OR1hahgq9cQVey4g9JmmGpVxrLjmdSMS\nZvvJ3HGzKERQw81qi1aibnx0/nbaXGshGhPlDzOflu4HAVBAjFUa8F3jp0xmZ6UkHpCzav\n/ZeCEUs3NK1dnIZKMjQ0+d2dmueC4w+QxPJn4c7Kb1jBAAAAgQDOP1ex1AsRuicwLhDK9F\nFUtL/C2ZaY9gFZI2AMtr0zWxCF6eufNzOjktwKGqcF1wdER8RDhhR5C+3tzoL77MF0mBJq\naQwHD8Fg88Non9wqg+PEu7O4ThAVCxCsFN12udGS3m3UvRP81SHtRve6jmgeDppbH+cqAt\nfeagfrZ91y7wAAAIEA1zSqG90Rl5n4b7iSrz2lisGqLcEXO/dfR5ElgRbxxjpsVsMZpuTf\nBib2pyh7m74+1gHKQXvztV3S2rWeVXrmglEwQM8UqPsCowBKw9JO9gtAC0vs6Vjp/kP3OR\nBVXq2DZR8BHOIBs5gvmSWa8a2+37IbBld+/NrTppTubNK+7M0AAACBAMeLyxqEfkJSFwJN\nleKoAfxl0i5u5vait2rp9YfQP/CGTJjJEMJ2AAch9Qo8aXPQaGi2csbNUSGsBS+OPKW92F\ncp3oGcRCg0mdMasjw0UCCse477qtWqAIB6LH4KMFCSsxYCH8GB6EfTIYmUswJhmDJm+0BC\n90B1BxJqQgZCAxdbAAAAGGFuc2libGUtZ2VuZXJhdGVkIG9uIHNobQEC\n-----END OPENSSH PRIVATE KEY-----\n',NULL,'2048 MD5:b9:4f:80:30:b7:a7:90:97:6f:2a:50:1a:74:65:dc:68 ansible-generated on shm (RSA)');

INSERT INTO `pay_systems` VALUES (1,'Платеж',NULL);

INSERT INTO `templates` VALUES (1,'web_tariff_create','Создание тарифа хостинга','Здравствуйте {{ user.full_name }}\n\nВы зарегистрировали новую услугу: {{ us.service.name }}\n\nДата истечения услуги: {{ us.expired }}\n\nСтоимость услуги: {{ us.service.cost }} руб.\n\nХостинг сайтов:\nХост: {{ child(\'web\').server.settings.host_name }}\nЛогин: {{ child(\'web\').settings.login }}\nПароль: {{ child(\'web\').settings.password }}\n\nЖелаем успехов.',NULL);

INSERT INTO `profiles` VALUES
(1,'40092','{"name": "Даниил", "email": "email@domain.ru", "index":"1234567", "phone":"+7(123) 123-45-67"}',DEFAULT)
;

INSERT INTO `config` VALUES
('_version','0.0.3'),
('_billing','Honest'),
('company_name','My Company LTD'),
('shm_url','http://admin.local'),
('mail_from','mail@domain.ru');

INSERT INTO `spool` (id,user_id,event) VALUES
(default,1,'{"title":"prolongate services","kind":"UserService","method":"prolongate","period":"60"}');

COMMIT;
