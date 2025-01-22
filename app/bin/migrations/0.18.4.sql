ALTER TABLE promo_codes ADD COLUMN `used_by` int(11) DEFAULT NULL;
UPDATE promo_codes SET used_by = user_id, user_id = 1;
