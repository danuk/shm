ALTER TABLE user_services DROP INDEX user_services_idx;
ALTER TABLE user_services DROP FOREIGN KEY user_services_ibfk_1;
ALTER TABLE user_services DROP FOREIGN KEY user_services_ibfk_2;
ALTER TABLE user_services DROP FOREIGN KEY user_services_ibfk_4;

ALTER TABLE withdraw_history DROP FOREIGN KEY withdraw_history_ibfk_1;
ALTER TABLE withdraw_history DROP FOREIGN KEY withdraw_history_ibfk_2;

ALTER TABLE bonus_history DROP FOREIGN KEY bonus_history_ibfk_1;