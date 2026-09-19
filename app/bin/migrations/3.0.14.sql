CREATE TABLE IF NOT EXISTS `logs_api` (
  `user_id` int(11) DEFAULT NULL,
  `date` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ip` varchar(45) NOT NULL,
  `url` varchar(512) NOT NULL,
  `method` varchar(10) NOT NULL,
  `args` json DEFAULT NULL,
  `descr` char(128) DEFAULT NULL,
  `duration` int(11) unsigned NOT NULL DEFAULT '0',
  `response_code` smallint(5) unsigned NOT NULL DEFAULT '0',
  `response_error` varchar(512) DEFAULT NULL,
  KEY `idx_logs_api_user_id` (`user_id`),
  KEY `idx_logs_api_date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
