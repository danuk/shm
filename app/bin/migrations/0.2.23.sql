ALTER TABLE servers ADD COLUMN services_count int(11) NOT NULL DEFAULT '0';
UPDATE servers RIGHT JOIN (SELECT settings->"$.server_id" as server_id, COUNT(user_services.settings->"$.server_id") as cnt FROM user_services WHERE status<>'REMOVED' GROUP BY user_services.settings-> "$.server_id") AS settings ON servers.server_id = settings.server_id SET servers.services_count = settings.cnt;

