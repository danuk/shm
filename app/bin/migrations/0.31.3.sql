DROP INDEX `PRIMARY` ON promo_codes;
ALTER TABLE promo_codes ADD PRIMARY KEY(id, user_id);
ALTER TABLE promo_codes ADD COLUMN `expire` datetime DEFAULT NULL;
