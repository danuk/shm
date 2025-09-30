ALTER TABLE spool DROP INDEX idx_spool_prio;
ALTER TABLE spool DROP INDEX idx_spool_status;

CREATE INDEX `idx_spool_select` ON spool(`prio`,`id`,`status`,`delayed`,`executed`);