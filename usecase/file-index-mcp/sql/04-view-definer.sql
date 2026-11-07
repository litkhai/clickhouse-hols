-- Fix for 02: run the view with the rights of a user that cannot log in and can only read the base table.
-- ai_reader keeps its single grant (SELECT on the view) and still cannot read fileidx.file_index directly.
CREATE USER IF NOT EXISTS fileidx_view_owner IDENTIFIED WITH no_password HOST NONE;
GRANT SELECT ON fileidx.file_index TO fileidx_view_owner;

CREATE OR REPLACE VIEW fileidx.files
DEFINER = fileidx_view_owner SQL SECURITY DEFINER
AS
SELECT root, path, name, ext, size, mtime, is_dir, depth, owner,
       content_hash, text_excerpt, indexed_at
FROM fileidx.file_index FINAL
WHERE is_deleted = 0;
