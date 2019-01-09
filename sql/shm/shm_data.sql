BEGIN;

INSERT INTO `users` VALUES
(1,0,'admin','0df78fa86a30eca0a918fdd21a94e238133ce7ab',0,NOW(),NULL,0,0,0,0.00,NULL,NULL,0,0,1,0,'Admin',0,0.00,NULL,NULL,NULL);

INSERT INTO `servers_groups` VALUES
(1,'Основная','random',NULL);

COMMIT;
