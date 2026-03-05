CREATE TABLE IF NOT EXISTS `statistics` (
  `date` date NOT NULL,
  `kind` varchar(32) NOT NULL DEFAULT '0.00',
  `field` varchar(32) NOT NULL DEFAULT '0',
  `count` int(11) NOT NULL DEFAULT '0',
  `sum` decimal(12,2) NOT NULL DEFAULT '0.00',
  `min` decimal(12,2) NOT NULL DEFAULT '0.00',
  `max` decimal(12,2) NOT NULL DEFAULT '0.00',
  `avg` decimal(12,2) NOT NULL DEFAULT '0.00',
  UNIQUE KEY (`date`, `kind`, `field`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;