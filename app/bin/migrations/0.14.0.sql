ALTER TABLE pays_history ADD COLUMN `uniq_key` char(255) DEFAULT NULL;
ALTER TABLE pays_history ADD UNIQUE KEY `uniq_key` (`user_id`,`uniq_key`);
