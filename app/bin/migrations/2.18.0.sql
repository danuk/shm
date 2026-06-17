ALTER TABLE `withdraw_history`
    DROP INDEX `idx_user_id`,
    ADD INDEX `idx_user_id_service_id` (`user_id`,`service_id`),
    ADD INDEX `idx_user_id_user_service_id` (`user_id`,`user_service_id`);
