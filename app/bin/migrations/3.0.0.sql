BEGIN;
SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create logins table (safe to run if already exists)
CREATE TABLE IF NOT EXISTS `logins` (
  `login` varchar(128) NOT NULL,
  `user_id` int(11) NOT NULL,
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`login`),
  KEY `idx_logins_user_id` (`user_id`),
  CONSTRAINT `fk_logins_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Copy primary logins from users.login
INSERT IGNORE INTO `logins` (`login`, `user_id`)
  SELECT LOWER(`login`), `user_id` FROM `users`;

-- 3. Copy secondary logins from users.login2 where they exist and are not duplicates
INSERT IGNORE INTO `logins` (`login`, `user_id`)
  SELECT LOWER(`login2`), `user_id` FROM `users`
  WHERE `login2` IS NOT NULL AND `login2` != '';

-- 4. Copy email from users.settings.email where set and not already in logins
INSERT IGNORE INTO `logins` (`login`, `user_id`, `settings`)
  SELECT LOWER(JSON_UNQUOTE(JSON_EXTRACT(`settings`, '$.email'))), `user_id`,
         JSON_OBJECT(
           'email', JSON_OBJECT(
             'verified', COALESCE(JSON_EXTRACT(`settings`, '$.email_verified'), 0)
           )
         )
  FROM `users`
  WHERE JSON_EXTRACT(`settings`, '$.email') IS NOT NULL
    AND JSON_EXTRACT(`settings`, '$.email') != 'null';

-- 4.1 Remove migrated legacy email fields from users.settings
UPDATE `users`
SET `settings` = JSON_REMOVE(`settings`, '$.email', '$.email_verified')
WHERE JSON_CONTAINS_PATH(`settings`, 'one', '$.email', '$.email_verified');

-- 4.2 Copy telegram user_id from users.settings.telegram.user_id as @<user_id> login
INSERT IGNORE INTO `logins` (`login`, `user_id`, `settings`)
  SELECT CONCAT('@', JSON_UNQUOTE(JSON_EXTRACT(`settings`, '$.telegram.user_id'))),
         `user_id`,
         JSON_OBJECT('telegram', JSON_EXTRACT(`settings`, '$.telegram'))
  FROM `users`
  WHERE JSON_EXTRACT(`settings`, '$.telegram.user_id') IS NOT NULL
    AND JSON_EXTRACT(`settings`, '$.telegram.user_id') != 'null'
    AND JSON_UNQUOTE(JSON_EXTRACT(`settings`, '$.telegram.user_id')) != '';

-- 4.3 Remove migrated telegram settings from users.settings
UPDATE `users`
SET `settings` = JSON_REMOVE(`settings`, '$.telegram')
WHERE JSON_CONTAINS_PATH(`settings`, 'one', '$.telegram');

-- 5. Remove login2 column from users (run after verifying the migration above)
ALTER TABLE `users` DROP KEY IF EXISTS `users_uniq`;
ALTER TABLE `users` DROP COLUMN IF EXISTS `login`;
ALTER TABLE `users` DROP KEY IF EXISTS `users_uniq_login2`;
ALTER TABLE `users` DROP COLUMN IF EXISTS `login2`;

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;

