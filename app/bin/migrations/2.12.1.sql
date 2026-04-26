ALTER TABLE `users`
    MODIFY COLUMN `login` varchar(128) NOT NULL,
    MODIFY COLUMN `login2` varchar(128) DEFAULT NULL;
