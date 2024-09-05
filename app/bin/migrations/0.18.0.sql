CREATE TABLE IF NOT EXISTS `promo_codes` (
  `id` char(32) NOT NULL,
  `template_id` char(32) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `used` datetime DEFAULT NULL,
  FOREIGN KEY (user_id) REFERENCES users (user_id),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

