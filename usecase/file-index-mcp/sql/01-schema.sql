-- Base table and the view the AI reads. Same DDL as the guide this lab checks, except the view (see 02).
CREATE DATABASE IF NOT EXISTS fileidx;

CREATE TABLE IF NOT EXISTS fileidx.file_index
(
    root          LowCardinality(String),   -- scan root name ('docs', 'archive')
    path          String,                   -- path relative to the root (the unique key)
    name          String,
    ext           LowCardinality(String),   -- lower case, no dot
    size          UInt64,
    mtime         DateTime,
    is_dir        UInt8,
    depth         UInt16,
    owner         LowCardinality(String) DEFAULT '',
    content_hash  String DEFAULT '',        -- optional: duplicate detection
    text_excerpt  String DEFAULT '',        -- optional: extracted text
    scan_id       UInt64,                   -- the scan that wrote this row
    is_deleted    UInt8 DEFAULT 0,
    indexed_at    DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(indexed_at)
ORDER BY (root, path)
SETTINGS index_granularity = 8192;
