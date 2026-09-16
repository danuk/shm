CREATE TABLE IF NOT EXISTS `spool_queues` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `rate_limit` float DEFAULT NULL COMMENT 'max tasks per second, NULL = unlimited',
  `status` enum('active','paused') NOT NULL DEFAULT 'active',
  `last_executed_at` datetime DEFAULT NULL COMMENT 'last time a task from this queue was executed',
  `created_at`       datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `finished_at`      datetime DEFAULT NULL COMMENT 'set automatically when no pending tasks remain',
  `total_added`  int(11) NOT NULL DEFAULT '0',
  `cnt_success`  int(11) NOT NULL DEFAULT '0',
  `cnt_fail`     int(11) NOT NULL DEFAULT '0',
  `cnt_delayed`  int(11) NOT NULL DEFAULT '0',
  `cnt_stuck`    int(11) NOT NULL DEFAULT '0',
  `cnt_paused`   int(11) NOT NULL DEFAULT '0',
  `cnt_skipped`  int(11) NOT NULL DEFAULT '0',
  `cnt_pending`  int(11) NOT NULL DEFAULT '0' COMMENT 'tasks not yet terminally finished',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `spool` ADD COLUMN `queue_id` int(11) DEFAULT NULL AFTER `settings`;
ALTER TABLE `spool_history` ADD COLUMN `queue_id` int(11) DEFAULT NULL AFTER `settings`;
ALTER TABLE `spool` ADD CONSTRAINT `fk_spool_queue` FOREIGN KEY (`queue_id`) REFERENCES `spool_queues` (`id`) ON DELETE SET NULL;
DROP INDEX `idx_spool_select` ON `spool`;
ALTER TABLE `spool` ADD KEY `idx_spool_select` (`prio`, `status`, `delayed`, `executed`, `queue_id`);
