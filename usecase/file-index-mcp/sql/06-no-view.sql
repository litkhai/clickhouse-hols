-- Alternative without a view: the engine drops deleted rows at FINAL (is_deleted parameter),
-- and the reader's own settings force FINAL. readonly = 1 stops the reader from turning it off.
CREATE TABLE IF NOT EXISTS fileidx.file_index_b AS fileidx.file_index
ENGINE = ReplacingMergeTree(indexed_at, is_deleted) ORDER BY (root, path);
INSERT INTO fileidx.file_index_b SELECT * FROM fileidx.file_index;

CREATE USER IF NOT EXISTS ai_reader_b IDENTIFIED WITH sha256_password BY '__AI_PASSWORD__'
SETTINGS readonly = 1, final = 1, max_result_rows = 20000, max_execution_time = 25, max_memory_usage = 4000000000;
GRANT SELECT(root, path, name, ext, size, mtime, is_dir, depth, owner, content_hash, text_excerpt, indexed_at)
  ON fileidx.file_index_b TO ai_reader_b;
