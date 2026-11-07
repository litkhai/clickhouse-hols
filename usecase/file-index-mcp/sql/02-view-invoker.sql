-- The guide's view, created as written. On 26.10 a normal view defaults to SQL SECURITY INVOKER
-- (default_normal_view_sql_security), so whoever reads it also needs SELECT on the base table.
CREATE VIEW IF NOT EXISTS fileidx.files AS
SELECT root, path, name, ext, size, mtime, is_dir, depth, owner,
       content_hash, text_excerpt, indexed_at
FROM fileidx.file_index FINAL
WHERE is_deleted = 0;
