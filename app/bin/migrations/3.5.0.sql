BEGIN;
SET FOREIGN_KEY_CHECKS = 0;

-- session_id is now stored in the DB as its sha256 hash (64 hex chars)
-- instead of plain text (see Core::Sessions::hash_id). Existing sessions
-- were created with the old plain-text `id`, so they are incompatible with
-- the new lookup format and must be purged. Affected users will simply
-- need to log in again.
DELETE FROM `sessions`;
ALTER TABLE `sessions` MODIFY COLUMN `id` char(64) NOT NULL;

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;
