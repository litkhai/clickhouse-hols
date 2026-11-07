-- Row policy order: one key with a live version (part 1) and a newer delete marker (part 2), merges stopped.
-- If the policy filtered before FINAL, the reader would see the old live version of '0'.
CREATE TABLE fileidx.rp_test AS fileidx.file_index ENGINE = ReplacingMergeTree(indexed_at) ORDER BY (root, path);
SYSTEM STOP MERGES fileidx.rp_test;
INSERT INTO fileidx.rp_test (root, path, name, ext, size, mtime, is_dir, depth, scan_id, indexed_at)
SELECT 'r', toString(number), toString(number), '', 1, now(), 0, 0, 1, now() - INTERVAL 10 DAY FROM numbers(3);
INSERT INTO fileidx.rp_test (root, path, name, ext, size, mtime, is_dir, depth, scan_id, is_deleted, indexed_at)
VALUES ('r', '0', '0', '', 1, now(), 0, 0, 2, 1, now() - INTERVAL 9 DAY);
GRANT SELECT ON fileidx.rp_test TO ai_reader_rp, indexer;
CREATE ROW POLICY IF NOT EXISTS live_only ON fileidx.rp_test USING is_deleted = 0 TO ai_reader_rp;
