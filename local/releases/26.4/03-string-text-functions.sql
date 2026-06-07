-- ClickHouse 26.4: obfuscateQuery + highlight + non-constant printf Test
-- New Features:
--   * obfuscateQuery(s)       — replace literals/identifiers with random-but-stable substitutes
--   * highlight(text, terms)  — wrap each occurrence of terms in HTML tags (<em>…</em>)
--   * printf — now accepts a non-constant format string (per-row format)
-- References:
--   https://github.com/ClickHouse/ClickHouse/pull/98305
--   https://github.com/ClickHouse/ClickHouse/pull/99131
--   https://github.com/ClickHouse/ClickHouse/pull/98991

-- ============================================
-- 1. obfuscateQuery — Safe Sharing of Query Patterns
-- ============================================

SELECT '========== 1. obfuscateQuery Basics ==========';

-- Identifiers and literals are replaced while preserving the SQL structure
SELECT obfuscateQuery('SELECT id, name FROM users WHERE id = 42') AS obfuscated;

SELECT obfuscateQuery('
    SELECT customer_id, sum(amount)
    FROM sales
    WHERE region = ''North America'' AND order_date >= ''2026-01-01''
    GROUP BY customer_id
    ORDER BY sum(amount) DESC
    LIMIT 100
') AS obfuscated;

-- Determinism: same input → same obfuscation
SELECT
    obfuscateQuery('SELECT 1') = obfuscateQuery('SELECT 1') AS is_deterministic;

-- ============================================
-- 2. Bulk Obfuscation of system.query_log Style Data
-- ============================================

SELECT '========== 2. Obfuscating a Batch of Queries ==========';

WITH sample_queries AS (
    SELECT arrayJoin([
        'SELECT count() FROM orders WHERE customer_id = 1234',
        'INSERT INTO events (user_id, action) VALUES (567, ''login'')',
        'SELECT order_id, total FROM orders WHERE region = ''EU'' AND total > 100'
    ]) AS query
)
SELECT
    query AS original,
    obfuscateQuery(query) AS shareable
FROM sample_queries;

-- ============================================
-- 3. highlight — Wrap Search Terms
-- ============================================

SELECT '========== 3. highlight() Basics ==========';

-- Default tags <em>...</em>
SELECT highlight('the quick brown fox jumps over the lazy dog', ['quick', 'fox', 'lazy']) AS html;

-- Multiple occurrences and overlaps
SELECT highlight('ClickHouse is fast. ClickHouse is open source.', ['ClickHouse', 'fast']) AS html;

-- Case-insensitive matching (ASCII)
SELECT highlight('Hello World hello WORLD', ['hello', 'world']) AS html;

-- Custom tags
SELECT highlight('apple banana cherry', ['banana'], '<mark>', '</mark>') AS html;

-- ============================================
-- 4. highlight in a Search-Results Pipeline
-- ============================================

SELECT '========== 4. Mock Search Results ==========';

DROP TABLE IF EXISTS articles;
CREATE TABLE articles (
    id     UInt32,
    title  String,
    body   String
) ENGINE = MergeTree() ORDER BY id;

INSERT INTO articles VALUES
    (1, 'Faster joins in ClickHouse 26.4', 'Memory-efficient grace hash joins keep big joins running within budget.'),
    (2, 'NATURAL JOIN syntax',             'NATURAL JOIN automatically matches by column name.'),
    (3, 'Array transpose',                 'arrayTranspose flips rows into columns for matrix-like data.');

-- Highlight the search term inside the body
SELECT
    title,
    highlight(body, ['joins', 'matrix', 'NATURAL']) AS highlighted_body
FROM articles
ORDER BY id;

-- ============================================
-- 5. printf with Non-Constant Format String
-- ============================================

SELECT '========== 5. Per-Row Format Strings ==========';

-- One format per row: decimal vs hex
WITH samples AS (
    SELECT * FROM (VALUES
        ('decimal', '%d',   42),
        ('hex',     '0x%X', 42),
        ('octal',   '%o',   42),
        ('padded',  '%05d', 42)
    ) AS t(label, fmt, n)
)
SELECT
    label,
    fmt,
    printf(fmt, n) AS formatted
FROM samples;

-- ============================================
-- 6. printf-Driven Per-Row Templates
-- ============================================

SELECT '========== 6. Mixed-Format Logging Output ==========';

WITH events AS (
    SELECT * FROM (VALUES
        ('login',     '[%s] user logged in',  'alice'),
        ('purchase',  '[%s] purchase made',   'bob'),
        ('logout',    '[%s] session ended',   'carol')
    ) AS t(event_type, fmt, args)
)
SELECT
    event_type,
    -- Apply different format strings per row to a single argument
    printf(fmt, args) AS rendered
FROM events;

-- ============================================
-- 7. Combined Pipeline: Search + Highlight + Format
-- ============================================

SELECT '========== 7. Pipeline: filter → highlight → format ==========';

SELECT
    printf('Article #%d: %s', id, highlight(title, ['ClickHouse', 'JOIN', 'array'])) AS line
FROM articles
ORDER BY id;

-- ============================================
-- Cleanup
-- ============================================

-- DROP TABLE IF EXISTS articles;

SELECT '========== Test Complete ==========';
SELECT 'obfuscateQuery + highlight + per-row printf round out the text-handling toolkit.' AS summary;
