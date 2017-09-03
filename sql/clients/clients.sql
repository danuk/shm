DROP TABLE IF exists `clients`;

CREATE TABLE `clients` (
      `client_id` int(11) NOT NULL AUTO_INCREMENT,
      `agent` char(64) DEFAULT NULL,
      `ip` char(15) DEFAULT NULL,
      `host` char(64) DEFAULT NULL,
      `db_user` char(64) DEFAULT NULL,
      `db_pass` char(64) DEFAULT NULL,
      `db_host` char(128) DEFAULT NULL,
      `db_name` char(64) DEFAULT NULL,
      `created` datetime DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`client_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

