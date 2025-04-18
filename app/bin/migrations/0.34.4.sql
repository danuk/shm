DROP INDEX `PRIMARY` ON promo_codes;
ALTER TABLE promo_codes MODIFY user_id INT NOT NULL;
ALTER TABLE promo_codes DROP KEY `user_id`;
ALTER TABLE promo_codes ADD PRIMARY KEY(id, user_id);