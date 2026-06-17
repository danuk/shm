SET @db := DATABASE();

SET @drop_sql := (
    SELECT IFNULL(
        CONCAT(
            'ALTER TABLE `withdraw_history` ',
            GROUP_CONCAT(
                CONCAT('DROP INDEX `', idx.index_name, '`')
                ORDER BY idx.index_name
                SEPARATOR ', '
            )
        ),
        'SELECT 1'
    )
    FROM (
        SELECT DISTINCT s.index_name
        FROM information_schema.statistics s
        WHERE s.table_schema = @db
          AND s.table_name = 'withdraw_history'
          AND s.index_name <> 'PRIMARY'
    ) idx
);

PREPARE stmt FROM @drop_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

ALTER TABLE `withdraw_history`
    ADD INDEX `idx_user_id_service_id` (`user_id`,`service_id`),
    ADD INDEX `idx_user_id_user_service_id` (`user_id`,`user_service_id`);
