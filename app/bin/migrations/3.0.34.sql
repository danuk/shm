UPDATE `users`
   SET `settings` = JSON_SET(COALESCE(`settings`, JSON_OBJECT()), '$.email', LOWER(`login2`))
 WHERE `login2` LIKE '_%@%.%'
   AND (
        `settings` IS NULL
     OR `settings` ->> '$.email' IS NULL
     OR `settings` ->> '$.email' IN ('', 'null')
   );

UPDATE `users`
   SET `login2` = NULL
 WHERE `login2` LIKE '_%@%.%';

UPDATE `users`
   SET `settings` = JSON_SET(`settings`, '$.email', LOWER(`settings` ->> '$.email'))
 WHERE JSON_TYPE(JSON_EXTRACT(`settings`, '$.email')) = 'STRING';

UPDATE `users`
   SET `login2` = CONCAT('@', `settings` ->> '$.telegram.user_id')
 WHERE `login2` IS NULL
   AND `settings` ->> '$.telegram.user_id' IS NOT NULL
   AND `settings` ->> '$.telegram.user_id' NOT IN ('', 'null')
   AND NOT EXISTS (
       SELECT 1 FROM (SELECT `login`, `login2` FROM `users`) u2
        WHERE u2.`login`  = CONCAT('@', `users`.`settings` ->> '$.telegram.user_id')
           OR u2.`login2` = CONCAT('@', `users`.`settings` ->> '$.telegram.user_id')
   );
