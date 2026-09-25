BEGIN;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS `user_groups` (
  `gid` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(255) NOT NULL,
  `is_admin` tinyint(4) NOT NULL DEFAULT '0',
  `default_policy` char(8) NOT NULL DEFAULT 'allow',
  `rules` json DEFAULT NULL,
  PRIMARY KEY (`gid`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `user_groups` (`gid`, `name`, `is_admin`, `default_policy`, `rules`) VALUES
(1, 'admins', 1, 'allow', NULL),
(2, 'users', 0, 'allow', NULL),
(3, 'Модератор', 1, 'deny', '[{"uri": "/admin/user", "action": "allow", "methods": ["GET", "POST"]}, {"uri": "/admin/user/search", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/accounts", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/service", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/service/*", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/pay", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/bonus", "action": "allow", "methods": ["GET"]}]'),
(4, 'Поддержка', 1, 'deny', '[{"uri": "/admin/user", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/search", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/accounts", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/service", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/service/*", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/pay", "action": "allow", "methods": ["GET"]}, {"uri": "/admin/user/bonus", "action": "allow", "methods": ["GET"]}]'),
(5, 'Viewer', 1, 'deny', '[{"uri": "/admin/*", "action": "allow", "methods": ["GET"]}]');

-- Пользователи без явной группы (gid не задан или равен 0) переводятся в
-- группу "users" (gid=2) - именно она и раньше соответствовала фактическому
-- поведению по умолчанию (разрешено всё, кроме /admin/*).
UPDATE `users` SET `gid` = 2 WHERE `gid` IS NULL OR `gid` = 0;

-- Явно фиксируем группу "users" (gid=2) как значение по умолчанию для новых
-- пользователей на уровне схемы.
ALTER TABLE `users` MODIFY COLUMN `gid` tinyint(4) NOT NULL DEFAULT '2';

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;
