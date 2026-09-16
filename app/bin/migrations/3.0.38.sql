BEGIN;
SET FOREIGN_KEY_CHECKS = 0;

-- 1. Migrate phone numbers from users.phone to accounts as cleaned (digits-only) logins
INSERT IGNORE INTO `accounts` (`login`, `user_id`, `type`, `settings`)
  SELECT REGEXP_REPLACE(`phone`, '[^0-9]', ''), `user_id`, 'phone',
         JSON_OBJECT('migrated_from', 'users.phone')
  FROM `users`
  WHERE `phone` IS NOT NULL
    AND REGEXP_REPLACE(`phone`, '[^0-9]', '') != '';

-- 2. Drop the now redundant phone column from users
ALTER TABLE `users` DROP COLUMN `phone`;

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;
