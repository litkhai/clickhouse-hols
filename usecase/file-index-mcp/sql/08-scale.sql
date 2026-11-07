-- 10M keys, then a second scan touching 1M of them and 100k delete markers: three ways to give a reader
-- only live rows, compared at a size where reading everything costs something. Own database, dropped by run.sh.
CREATE DATABASE IF NOT EXISTS fileidx_scale;
CREATE TABLE fileidx_scale.file_index AS fileidx.file_index ENGINE = ReplacingMergeTree(indexed_at) ORDER BY (root, path);
INSERT INTO fileidx_scale.file_index (root, path, name, ext, size, mtime, is_dir, depth, scan_id, indexed_at)
SELECT ['docs','archive'][number % 2 + 1], concat('d', toString(intDiv(number, 1000)), '/f', toString(number), '.', ['pdf','docx','jpg','mp4','zip'][number % 5 + 1]),
       concat('f', toString(number), '.', ['pdf','docx','jpg','mp4','zip'][number % 5 + 1]), ['pdf','docx','jpg','mp4','zip'][number % 5 + 1],
       cityHash64(number) % 100000000, toDateTime('2019-01-01') + (cityHash64(number, 1) % 250000000), 0, 1, 1, now() - INTERVAL 2 DAY
FROM numbers(10000000);
INSERT INTO fileidx_scale.file_index (root, path, name, ext, size, mtime, is_dir, depth, scan_id, indexed_at)
SELECT ['docs','archive'][number % 2 + 1], concat('d', toString(intDiv(number, 1000)), '/f', toString(number), '.', ['pdf','docx','jpg','mp4','zip'][number % 5 + 1]),
       concat('f', toString(number), '.', ['pdf','docx','jpg','mp4','zip'][number % 5 + 1]), ['pdf','docx','jpg','mp4','zip'][number % 5 + 1],
       cityHash64(number) % 100000000 + 1, now(), 0, 1, 2, now() - INTERVAL 1 DAY
FROM numbers(0, 10000000, 10);
INSERT INTO fileidx_scale.file_index (root, path, name, ext, size, mtime, is_dir, depth, scan_id, is_deleted, indexed_at)
SELECT ['docs','archive'][number % 2 + 1], concat('d', toString(intDiv(number, 1000)), '/f', toString(number), '.', ['pdf','docx','jpg','mp4','zip'][number % 5 + 1]),
       '', '', 0, now(), 0, 1, 3, 1, now()
FROM numbers(5, 10000000, 100);

-- A: DEFINER view (the fix from 04)
CREATE USER IF NOT EXISTS scale_view_owner IDENTIFIED WITH no_password HOST NONE;
GRANT SELECT ON fileidx_scale.file_index TO scale_view_owner;
CREATE VIEW fileidx_scale.files DEFINER = scale_view_owner SQL SECURITY DEFINER AS
SELECT root, path, name, ext, size, mtime, is_dir, depth, owner, content_hash, text_excerpt, indexed_at
FROM fileidx_scale.file_index FINAL WHERE is_deleted = 0;
GRANT SELECT ON fileidx_scale.files TO ai_reader;

-- B: no view, is_deleted engine parameter + final = 1 (the design from 06)
CREATE TABLE fileidx_scale.file_index_b AS fileidx_scale.file_index ENGINE = ReplacingMergeTree(indexed_at, is_deleted) ORDER BY (root, path);
INSERT INTO fileidx_scale.file_index_b SELECT * FROM fileidx_scale.file_index;
GRANT SELECT ON fileidx_scale.file_index_b TO ai_reader_b;

-- C: no view, the same table, a row policy + final = 1
CREATE USER IF NOT EXISTS ai_reader_rp IDENTIFIED WITH sha256_password BY '__AI_PASSWORD__'
SETTINGS readonly = 1, final = 1, max_result_rows = 20000, max_execution_time = 25, max_memory_usage = 4000000000;
GRANT SELECT ON fileidx_scale.file_index TO ai_reader_rp;
CREATE ROW POLICY IF NOT EXISTS live_only ON fileidx_scale.file_index USING is_deleted = 0 TO ai_reader_rp;
