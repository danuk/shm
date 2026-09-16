BEGIN;
SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create accounts table (safe to run if already exists)
CREATE TABLE IF NOT EXISTS `accounts` (
  `login` varchar(128) NOT NULL,
  `type` char(16) NOT NULL DEFAULT 'login',
  `user_id` int(11) NOT NULL,
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`login`, `type`),
  KEY `idx_accounts_user_id` (`user_id`),
  CONSTRAINT `fk_accounts_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Copy primary accounts from users.login
INSERT IGNORE INTO `accounts` (`login`, `user_id`, `type`)
  SELECT LOWER(`login`), `user_id`, 'login' FROM `users`;

-- 3. Copy secondary accounts from users.login2 where they exist and are not duplicates
INSERT IGNORE INTO `accounts` (`login`, `user_id`, `type`)
  SELECT LOWER(`login2`), `user_id`, 'login' FROM `users`
  WHERE `login2` IS NOT NULL AND `login2` != '';

-- 4. Copy email from users.settings.email where set and not already in accounts
INSERT IGNORE INTO `accounts` (`login`, `user_id`, `type`, `settings`)
  SELECT LOWER(JSON_UNQUOTE(JSON_EXTRACT(`settings`, '$.email'))), `user_id`, 'email',
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

-- 4.2 Copy telegram user_id from users.settings.telegram.user_id as login
INSERT IGNORE INTO `accounts` (`login`, `user_id`, `type`, `settings`)
  SELECT JSON_UNQUOTE(JSON_EXTRACT(`settings`, '$.telegram.user_id')),
         `user_id`, 'telegram',
         JSON_OBJECT('telegram', JSON_EXTRACT(`settings`, '$.telegram'))
  FROM `users`
  WHERE JSON_EXTRACT(`settings`, '$.telegram.user_id') IS NOT NULL
    AND JSON_EXTRACT(`settings`, '$.telegram.user_id') != 'null'
    AND JSON_UNQUOTE(JSON_EXTRACT(`settings`, '$.telegram.user_id')) != '';

-- 4.3 Remove migrated telegram settings from users.settings
-- UPDATE `users`
-- SET `settings` = JSON_REMOVE(`settings`, '$.telegram')
-- WHERE JSON_CONTAINS_PATH(`settings`, 'one', '$.telegram');

-- 5. Remove login2 column from users (run after verifying the migration above)
-- ALTER TABLE `users` DROP KEY `users_uniq`;
-- ALTER TABLE `users` DROP KEY `users_uniq_login2`;
-- ALTER TABLE `users` DROP COLUMN `login2`;

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;
