-- ClickHouse 26.2: xxh3_128 Hash Function Test
-- New Feature: 128-bit XXH3 non-cryptographic hash, complementing existing xxHash64
-- Reference: https://github.com/ClickHouse/ClickHouse/pull/96055

-- ============================================
-- 1. Basic Usage
-- ============================================

SELECT '========== 1. Basic xxh3_128 Usage ==========';

-- Hash various inputs
SELECT
    hex(xxh3_128('hello world')) AS hex_hash,
    xxh3_128('hello world')      AS uint128_hash,
    toTypeName(xxh3_128('hello world')) AS result_type;

-- Same input → same hash (determinism)
SELECT
    xxh3_128('clickhouse') = xxh3_128('clickhouse') AS deterministic;

-- Different inputs → different hashes
SELECT
    xxh3_128('apple') != xxh3_128('banana') AS distinct_hashes;

-- ============================================
-- 2. Comparison with Other Hash Functions
-- ============================================

SELECT '========== 2. Compare 64-bit xxHash64 vs 128-bit xxh3_128 ==========';

WITH 'The quick brown fox jumps over the lazy dog' AS s
SELECT
    s,
    hex(xxHash64(s)) AS xxHash64_hex,
    hex(xxh3_128(s)) AS xxh3_128_hex,
    length(hex(xxHash64(s))) AS bits_64_hex_len,
    length(hex(xxh3_128(s))) AS bits_128_hex_len;

-- ============================================
-- 3. Bulk Hashing for Deduplication
-- ============================================

SELECT '========== 3. Deduplication via xxh3_128 Fingerprint ==========';

DROP TABLE IF EXISTS documents;
CREATE TABLE documents
(
    doc_id     UInt32,
    title      String,
    body       String,
    fingerprint UInt128 MATERIALIZED xxh3_128(concat(title, '|', body))
) ENGINE = MergeTree()
ORDER BY doc_id;

-- Rows 3 and 5 are intentional duplicates of rows 1 and 2 (same title+body)
INSERT INTO documents (doc_id, title, body) VALUES
    (1, 'Welcome',          'Hello and welcome to ClickHouse.'),
    (2, 'Release Notes',    'ClickHouse 26.2 includes xxh3_128.'),
    (3, 'Welcome',          'Hello and welcome to ClickHouse.'),
    (4, 'Bug Fix',          'Memory leak resolved.'),
    (5, 'Release Notes',    'ClickHouse 26.2 includes xxh3_128.');

-- Group documents by their content fingerprint to find duplicates
SELECT
    fingerprint,
    count()           AS dup_count,
    groupArray(doc_id) AS doc_ids,
    any(title)        AS sample_title
FROM documents
GROUP BY fingerprint
HAVING dup_count > 1
ORDER BY dup_count DESC;

-- ============================================
-- 4. Hash-Based Sharding Key
-- ============================================

SELECT '========== 4. Hash Sharding (8 Buckets) ==========';

WITH users AS (
    SELECT arrayJoin(['alice','bob','carol','dave','eve','frank','grace','henry','irene','jane']) AS username
)
SELECT
    username,
    xxh3_128(username) % 8 AS shard
FROM users
ORDER BY username;

-- Shard size distribution
SELECT
    shard,
    count() AS n,
    groupArray(username) AS members
FROM (
    SELECT
        arrayJoin(['alice','bob','carol','dave','eve','frank','grace','henry','irene','jane',
                   'kate','leo','mia','noah','olivia','peter','quinn','ruth','sam','tina']) AS username,
        xxh3_128(username) % 4 AS shard
)
GROUP BY shard
ORDER BY shard;

-- ============================================
-- 5. Collision Resistance: 10k Random Strings
-- ============================================

SELECT '========== 5. Collision Test on 10,000 Random Strings ==========';

SELECT
    count()              AS total_rows,
    uniqExact(s)         AS unique_inputs,
    uniqExact(h64)       AS unique_xxHash64,
    uniqExact(h128)      AS unique_xxh3_128
FROM (
    SELECT
        randomString(20) AS s,
        xxHash64(s)  AS h64,
        xxh3_128(s) AS h128
    FROM numbers(10000)
);

-- ============================================
-- 6. Joining on 128-bit Fingerprints
-- ============================================

SELECT '========== 6. JOIN on xxh3_128 Fingerprint ==========';

DROP TABLE IF EXISTS docs_a;
DROP TABLE IF EXISTS docs_b;

CREATE TABLE docs_a (id UInt32, body String) ENGINE = MergeTree() ORDER BY id;
CREATE TABLE docs_b (id UInt32, body String) ENGINE = MergeTree() ORDER BY id;

INSERT INTO docs_a VALUES (1, 'shared content A'), (2, 'unique to a'), (3, 'shared content B');
INSERT INTO docs_b VALUES (10, 'shared content A'), (11, 'unique to b'), (12, 'shared content B');

-- Find rows in B whose body matches any row in A (compared by 128-bit fingerprint)
SELECT
    a.id AS a_id,
    b.id AS b_id,
    a.body
FROM docs_a AS a
INNER JOIN docs_b AS b ON xxh3_128(a.body) = xxh3_128(b.body)
ORDER BY a.id, b.id;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS documents;
-- DROP TABLE IF EXISTS docs_a;
-- DROP TABLE IF EXISTS docs_b;

SELECT '========== Test Complete ==========';
SELECT 'xxh3_128 doubles the hash space of xxHash64 with the same speed profile.' AS summary;
