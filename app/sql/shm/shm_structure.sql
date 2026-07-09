BEGIN;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS `acts` (
  `act_id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `date` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `show_act` tinyint(4) DEFAULT NULL,
  FOREIGN KEY (user_id) REFERENCES users (user_id),
  PRIMARY KEY (`act_id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `acts_data` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `act_id` int(10) unsigned DEFAULT NULL,
  `user_id` int(11) NOT NULL,
  `service_id` int(11) DEFAULT NULL,
  `user_service_id` int(11) DEFAULT NULL,
  `withdraw_id` int(10) unsigned DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `name` char(64) DEFAULT NULL,
  `start_date` datetime DEFAULT NULL,
  `stop_date` datetime DEFAULT NULL,
  FOREIGN KEY (user_id) REFERENCES users (user_id),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `apps` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `user_service_id` int(11) NOT NULL,
  `name` char(16) NOT NULL,
  `domain_id` int(11) DEFAULT NULL,
  `settings` json DEFAULT NULL,
  FOREIGN KEY (user_id) REFERENCES users (user_id),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `discounts` (
  `discount_id` tinyint(4) NOT NULL AUTO_INCREMENT,
  `title` char(64) NOT NULL,
  `months` decimal(10,4) NOT NULL,
  `percent` tinyint(4) NOT NULL,
  `share` tinyint(4) DEFAULT NULL,
  PRIMARY KEY (`discount_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `dns_services` (
  `dns_id` int(11) NOT NULL AUTO_INCREMENT,
  `domain_id` int(11) NOT NULL,
  `domain` char(255) DEFAULT NULL,
  `type` char(5) DEFAULT NULL,
  `prio` tinyint(4) DEFAULT NULL,
  `addr` text,
  `ttl` tinyint(4) DEFAULT NULL,
  FOREIGN KEY (domain_id) REFERENCES domains (domain_id),
  PRIMARY KEY (`dns_id`)
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `domains` (
  `domain_id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `domain` char(64) NOT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `zone_id` int(11) DEFAULT NULL,
  `subdomain_for` int(11) DEFAULT NULL,
  `punycode` char(64) DEFAULT NULL,
  `user_service_id` int(11) DEFAULT NULL,
  FOREIGN KEY (user_id) REFERENCES users (user_id),
  PRIMARY KEY (`domain_id`),
  UNIQUE KEY `domain` (`domain`)
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `domains_services` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `domain_id` int(11) NOT NULL,
  `user_service_id` int(11) NOT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `domain_service_id` (`domain_id`,`user_service_id`)
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `invoices` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `date` int(11) DEFAULT NULL,
  `user_id` int(11) DEFAULT NULL,
  `total` decimal(10,2) DEFAULT '0.00',
  `text` char(128) DEFAULT NULL,
  FOREIGN KEY (user_id) REFERENCES users (user_id),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pays_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `pay_system_id` char(32) DEFAULT NULL,
  `money` decimal(10,2) NOT NULL DEFAULT '0.00',
  `date` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `comment` json DEFAULT NULL,
  `uniq_key` char(255) DEFAULT NULL,
  UNIQUE KEY `uniq_key` (`user_id`,`uniq_key`),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `servers` (
  `server_id` int(11) NOT NULL AUTO_INCREMENT,
  `server_gid` int(11) DEFAULT NULL,
  `name` char(255) DEFAULT NULL,
  `transport` char(32) NOT NULL,
  `host` char(255) DEFAULT NULL,
  `ip` char(15) DEFAULT NULL,
  `weight` int(11) DEFAULT '100',
  `success_count` int(11) NOT NULL DEFAULT '0',
  `fail_count` int(11) NOT NULL DEFAULT '0',
  `services_count` int(11) NOT NULL DEFAULT '0',
  `enabled` int(1) NOT NULL DEFAULT '1',
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`server_id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `servers_groups` (
  `group_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(255) DEFAULT NULL,
  `transport` char(32) NOT NULL DEFAULT 'ssh',
  `type` char(16) NOT NULL DEFAULT 'random',
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`group_id`)
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `services` (
  `service_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(64) NOT NULL,
  `cost` decimal(10,2) DEFAULT NULL,
  `period` decimal(10,4) NOT NULL DEFAULT '1',
  `category` char(16) DEFAULT NULL,
  `children` json DEFAULT NULL,
  `next` int(11) DEFAULT '0',
  `allow_to_order` tinyint(4) DEFAULT NULL,
  `max_count` tinyint(4) DEFAULT NULL,
  `question` tinyint(4) DEFAULT NULL,
  `pay_always` tinyint(4) DEFAULT '0',
  `no_discount` tinyint(4) DEFAULT '0',
  `descr` char(255) DEFAULT NULL,
  `pay_in_credit` tinyint(4) DEFAULT '0',
  `config` json DEFAULT NULL,
  `is_composite` tinyint(4) NOT NULL DEFAULT '0',
  `deleted` tinyint(4) NOT NULL DEFAULT '0',
  PRIMARY KEY (`service_id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `events` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `kind` char(32) NOT NULL,
  `title` char(128) NOT NULL,
  `name` char(32) NOT NULL,
  `server_gid` int(11) DEFAULT NULL,
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `spool` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `user_service_id` int(11) DEFAULT NULL,
  `response` json DEFAULT NULL,
  `event` json NOT NULL,
  `prio` int(11) NOT NULL DEFAULT '0',
  `status` char(8) DEFAULT 'NEW',
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `executed` datetime DEFAULT NULL,
  `delayed` int(11) NOT NULL DEFAULT '0',
  `settings` json DEFAULT NULL,
  KEY idx_spool_select (`prio`,`status`,`delayed`,`executed`),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `spool_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `spool_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `user_service_id` int(11) DEFAULT NULL,
  `response` json DEFAULT NULL,
  `event` json DEFAULT NULL,
  `prio` int(11) NOT NULL DEFAULT '0',
  `status` char(8) DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `executed` datetime DEFAULT NULL,
  `delayed` int(11) NOT NULL DEFAULT '0',
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `user_services` (
  `user_service_id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `service_id` int(11) NOT NULL,
  `auto_bill` tinyint(4) NOT NULL DEFAULT '1',
  `withdraw_id` int(11) DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expire` datetime DEFAULT NULL,
  `status_before` char(8) NOT NULL,
  `status` char(8) NOT NULL,
  `next` int(11) DEFAULT NULL,
  `parent` int(11) DEFAULT NULL,
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`user_service_id`),
  FOREIGN KEY (parent) REFERENCES user_services (user_service_id) ON DELETE SET NULL,
  KEY idx_user_id (user_id)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `users` (
  `user_id` int(11) NOT NULL AUTO_INCREMENT,
  `partner_id` int(11) DEFAULT NULL,
  `login` varchar(128) NOT NULL,
  `password` varchar(128) DEFAULT NULL,
  `type` tinyint(4) DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_login` datetime DEFAULT NULL,
  `discount` tinyint(4) NOT NULL DEFAULT '0',
  `balance` decimal(10,2) NOT NULL,
  `credit` decimal(10,2) NOT NULL,
  `comment` char(255) DEFAULT NULL,
  `dogovor` char(32) DEFAULT NULL,
  `block` tinyint(4) NOT NULL DEFAULT '0',
  `gid` tinyint(4) DEFAULT NULL,
  `perm_credit` tinyint(4) DEFAULT '0',
  `full_name` char(255) DEFAULT NULL,
  `can_overdraft` tinyint(4) DEFAULT '0',
  `bonus` decimal(10,2) NOT NULL,
  `phone` char(20) DEFAULT NULL,
  `verified` int(11) DEFAULT NULL,
  `create_act` tinyint(4) DEFAULT NULL,
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `accounts` (
  `login` varchar(128) NOT NULL,
  `type` char(16) NOT NULL DEFAULT 'login',
  `user_id` int(11) NOT NULL,
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`login`, `type`),
  KEY `idx_accounts_user_id` (`user_id`),
  CONSTRAINT `fk_accounts_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `accounts` (
  `login` varchar(128) NOT NULL,
  `type` char(16) NOT NULL DEFAULT 'login',
  `user_id` int(11) NOT NULL,
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`login`, `type`),
  KEY `idx_accounts_user_id` (`user_id`),
  CONSTRAINT `fk_accounts_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `withdraw_history` (
  `withdraw_id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `create_date` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `withdraw_date` datetime DEFAULT NULL,
  `end_date` datetime DEFAULT NULL,
  `cost` decimal(10,2) NOT NULL DEFAULT '0.00',
  `discount` tinyint(2) NOT NULL DEFAULT '0',
  `bonus` decimal(10,2) NOT NULL DEFAULT '0.00',
  `months` decimal(10,4) NOT NULL DEFAULT '1',
  `total` decimal(10,2) NOT NULL DEFAULT '0.00',
  `service_id` int(11) NOT NULL,
  `qnt` double NOT NULL DEFAULT '1',
  `user_service_id` int(11) NOT NULL,
  PRIMARY KEY (`withdraw_id`),
  KEY idx_user_id_service_id (`user_id`,`service_id`),
  KEY idx_user_id_user_service_id (`user_id`,`user_service_id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `zones` (
  `zone_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(32) NOT NULL,
  `order` tinyint(4) NOT NULL DEFAULT '0',
  `server` char(64) DEFAULT NULL,
  `query` char(128) DEFAULT NULL,
  `service_id` int(11) DEFAULT NULL,
  `min_lenght` tinyint(4) DEFAULT NULL,
  `disabled` tinyint(4) DEFAULT '0',
  `nic_service` char(16) DEFAULT NULL,
  `nic_template` char(16) DEFAULT NULL,
  `contract` tinyint(4) DEFAULT '0',
  `idn` tinyint(4) DEFAULT '0',
  `punycode_only` tinyint(4) DEFAULT '0',
  PRIMARY KEY (`zone_id`)
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `identities` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(64) NOT NULL,
  `private_key` text NOT NULL,
  `public_key` text,
  `fingerprint` char(128),
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `templates` (
  `id` char(32) NOT NULL,
  `data` MEDIUMTEXT DEFAULT NULL, -- Up to 16 Mb
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `console` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `start` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `stop` datetime DEFAULT NULL,
  `log` MEDIUMBLOB NOT NULL,
  `eof` boolean DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `profiles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `data` json DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users (user_id),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `config` (
  `key` char(32) NOT NULL,
  `value` json DEFAULT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sessions` (
  `id` char(32) NOT NULL,
  `user_id` int(11) NOT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `storage` (
  `user_id` int(11) NOT NULL,
  `name` char(32) NOT NULL,
  `user_service_id` int(11) DEFAULT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `data` MEDIUMBLOB DEFAULT NULL, -- Up to 16 Mb
  `settings` json DEFAULT NULL,
  PRIMARY KEY (`user_id`,`name`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bonus_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `date` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `bonus` decimal(10,2) NOT NULL,
  `comment` json DEFAULT NULL,
  KEY idx_user_id (user_id),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `promo_codes` (
  `id` char(32) NOT NULL,
  `user_id` int(11) NOT NULL,
  `template_id` char(32) NOT NULL,
  `created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `used` datetime DEFAULT NULL,
  `used_by` int(11) DEFAULT NULL,
  `settings` json DEFAULT NULL,
  `expire` datetime DEFAULT NULL,
  PRIMARY KEY (`id`,`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;
