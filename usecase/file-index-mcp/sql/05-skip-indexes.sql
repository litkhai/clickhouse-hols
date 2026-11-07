-- The guide's optional indexes (tokenbf_v1, ngrambf_v1: listed as deprecated in the current MergeTree docs)
-- and, for comparison, a text index (the docs: GA from 26.2).
ALTER TABLE fileidx.file_index ADD INDEX IF NOT EXISTS idx_text text_excerpt TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4;
ALTER TABLE fileidx.file_index ADD INDEX IF NOT EXISTS idx_name name TYPE ngrambf_v1(4, 16384, 3, 0) GRANULARITY 4;
ALTER TABLE fileidx.file_index ADD INDEX IF NOT EXISTS idx_text_inv text_excerpt TYPE text(tokenizer = splitByNonAlpha);
ALTER TABLE fileidx.file_index MATERIALIZE INDEX idx_text SETTINGS mutations_sync = 2;
ALTER TABLE fileidx.file_index MATERIALIZE INDEX idx_name SETTINGS mutations_sync = 2;
ALTER TABLE fileidx.file_index MATERIALIZE INDEX idx_text_inv SETTINGS mutations_sync = 2;
