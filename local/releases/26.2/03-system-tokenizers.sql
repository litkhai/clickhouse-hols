-- ClickHouse 26.2: system.tokenizers Catalog Test
-- New Feature: system.tokenizers exposes every tokenizer available to text indexes
-- Reference: https://github.com/ClickHouse/ClickHouse/pull/96753

-- ============================================
-- 1. Inspect the Tokenizer Catalog
-- ============================================

SELECT '========== 1. All Available Tokenizers ==========';

SELECT *
FROM system.tokenizers
ORDER BY name;

-- ============================================
-- 2. Use Each Tokenizer via tokens() Function
-- ============================================

SELECT '========== 2. tokens() with Different Tokenizers ==========';

WITH 'ClickHouse 26.2: full-text search with text indexes!' AS sample
SELECT 'splitByNonAlpha (default)' AS tokenizer, tokens(sample, 'splitByNonAlpha') AS result
UNION ALL
SELECT 'splitByString:space'      AS tokenizer, tokens(sample, 'splitByString', [' ']) AS result
UNION ALL
SELECT 'ngrams(3)'                AS tokenizer, tokens(sample, 'ngrams', 3) AS result
ORDER BY tokenizer;

-- ============================================
-- 3. Build a Searchable Article Table
-- ============================================

SELECT '========== 3. Article Table with Text Index ==========';

DROP TABLE IF EXISTS articles;
CREATE TABLE articles
(
    id      UInt32,
    title   String,
    body    String,
    INDEX body_text_idx body TYPE text(tokenizer='splitByNonAlpha') GRANULARITY 1
) ENGINE = MergeTree()
ORDER BY id
SETTINGS index_granularity = 4;

INSERT INTO articles VALUES
    (1, 'ClickHouse 26.2 release',     'system.tokenizers, primes function, xxh3_128 hash and more.'),
    (2, 'Full-text search basics',     'The text index uses tokenizers to break strings into terms.'),
    (3, 'Sharding strategies',         'xxh3_128 produces a wide hash useful for shard mapping.'),
    (4, 'Number theory in SQL',        'primes() table function lets you query primes directly.'),
    (5, 'Indexing JSON arrays',        'Use text indexes on Array(String) for tag search.'),
    (6, 'Keeper monitoring',           'Keeper exposes an HTTP API for status and metrics.');

-- ============================================
-- 4. Full-Text Search Using the Index
-- ============================================

SELECT '========== 4. Full-Text Search Queries ==========';

-- Single term match
SELECT id, title
FROM articles
WHERE hasToken(body, 'primes')
ORDER BY id;

-- Multi-term AND
SELECT id, title
FROM articles
WHERE hasToken(body, 'text') AND hasToken(body, 'index')
ORDER BY id;

-- Match against title (no index)
SELECT id, title
FROM articles
WHERE title ILIKE '%search%'
ORDER BY id;

-- ============================================
-- 5. Token Counts per Document
-- ============================================

SELECT '========== 5. Token Counts (default tokenizer) ==========';

SELECT
    id,
    title,
    length(tokens(body)) AS token_count,
    tokens(body)         AS body_tokens
FROM articles
ORDER BY id;

-- ============================================
-- 6. Verify Index Was Used
-- ============================================

SELECT '========== 6. Explain Plan: Index Usage ==========';

EXPLAIN indexes = 1
SELECT id
FROM articles
WHERE hasToken(body, 'primes')
FORMAT TSVRaw;

-- ============================================
-- 7. Compare Tokenizer Behavior on Mixed Text
-- ============================================

SELECT '========== 7. Same Input, Different Tokenizers ==========';

WITH 'name@host.com user_id=42 OK!' AS s
SELECT 'splitByNonAlpha' AS tokenizer, tokens(s, 'splitByNonAlpha') AS result
UNION ALL
SELECT 'ngrams(4)'       AS tokenizer, tokens(s, 'ngrams', 4)       AS result
UNION ALL
SELECT 'splitByString:=' AS tokenizer, tokens(s, 'splitByString', ['=']) AS result
ORDER BY tokenizer;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS articles;

SELECT '========== Test Complete ==========';
SELECT 'system.tokenizers makes the text-index tokenizer catalog discoverable from SQL.' AS summary;
