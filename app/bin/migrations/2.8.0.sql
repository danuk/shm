ALTER TABLE `users` ADD COLUMN `login2` char(64) DEFAULT NULL AFTER `login`;
UPDATE `users` SET `login2` = CONCAT('@', `settings` ->> '$.telegram.user_id') WHERE `settings` ->> '$.telegram.user_id' IS NOT NULL AND `login` != CONCAT('@', `settings` ->> '$.telegram.user_id');
ALTER TABLE `users` ADD UNIQUE KEY `users_uniq_login2` (`login2`);