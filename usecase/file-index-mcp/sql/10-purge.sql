-- Cleaning up delete markers. Same start in each table: 3 live rows indexed 10 days ago (part 1) and a
-- marker for '0' from 9 days ago (part 2), merges stopped until the cleanup statement runs.
CREATE TABLE fileidx.purge_ttl AS fileidx.file_index ENGINE = ReplacingMergeTree(indexed_at) ORDER BY (root, path);
CREATE TABLE fileidx.purge_ttl_where AS fileidx.file_index ENGINE = ReplacingMergeTree(indexed_at) ORDER BY (root, path);
CREATE TABLE fileidx.purge_delete AS fileidx.file_index ENGINE = ReplacingMergeTree(indexed_at) ORDER BY (root, path);
CREATE TABLE fileidx.purge_cleanup AS fileidx.file_index ENGINE = ReplacingMergeTree(indexed_at, is_deleted) ORDER BY (root, path)
SETTINGS allow_experimental_replacing_merge_with_cleanup = 1;
