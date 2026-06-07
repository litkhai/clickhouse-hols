-- ClickHouse 26.5: tokenizeQuery + highlightQuery Test
-- New Features:
--   * tokenizeQuery(s)  — returns Array(Tuple(start, end, token_type)) of lexer tokens
--   * highlightQuery(s) — returns Array(Tuple(start, end, highlight_category)) of parser-based syntax highlight ranges
-- Reference: https://github.com/ClickHouse/ClickHouse/pull/101054

-- ============================================
-- 1. tokenizeQuery — Lexer-Level Token Stream
-- ============================================

SELECT '========== 1. tokenizeQuery Basics ==========';

-- Returns Array of (start_offset, end_offset, token_type) tuples
SELECT tokenizeQuery('SELECT 1 + 2 FROM t') AS tokens;

-- More complex query
SELECT tokenizeQuery('SELECT id, sum(amount) AS total FROM orders WHERE region = ''NA'' GROUP BY id') AS tokens;

-- ============================================
-- 2. Decompose Each Token Into Its Own Row
-- ============================================

SELECT '========== 2. Token-By-Token Decomposition ==========';

WITH q AS (SELECT 'SELECT id, name FROM users WHERE id = 42' AS sql),
tok AS (
    SELECT
        sql,
        tokenizeQuery(sql) AS tokens
    FROM q
)
SELECT
    t.1 AS start_pos,
    t.2 AS end_pos,
    t.3 AS token_type,
    substring(sql, t.1 + 1, t.2 - t.1) AS lexeme
FROM tok
ARRAY JOIN tokens AS t
ORDER BY start_pos;

-- ============================================
-- 3. Token-Type Frequency
-- ============================================

SELECT '========== 3. Token-Type Frequency in a Query ==========';

WITH q AS (SELECT '
    SELECT customer_id, count(), sum(amount) AS total
    FROM sales JOIN customers USING (customer_id)
    WHERE order_date >= ''2026-01-01''
    GROUP BY customer_id
    ORDER BY total DESC
    LIMIT 10
' AS sql)
SELECT
    t.3 AS token_type,
    count() AS occurrences
FROM q
ARRAY JOIN tokenizeQuery(sql) AS t
GROUP BY token_type
ORDER BY occurrences DESC, token_type;

-- ============================================
-- 4. highlightQuery — Parser-Driven Syntax Highlighting
-- ============================================

SELECT '========== 4. highlightQuery Basics ==========';

-- Returns Array of (start_offset, end_offset, category) tuples
SELECT highlightQuery('SELECT name FROM users WHERE id = 1') AS highlights;

SELECT highlightQuery('CREATE TABLE t (a UInt32, b String) ENGINE = MergeTree() ORDER BY a') AS highlights;

-- ============================================
-- 5. Build a Plain-Text Highlighted View
-- ============================================

SELECT '========== 5. Token-By-Token Highlight Categories ==========';

WITH q AS (SELECT 'SELECT id, name FROM users WHERE id = 1' AS sql),
hi AS (
    SELECT sql, highlightQuery(sql) AS hl FROM q
)
SELECT
    h.1 AS start_pos,
    h.2 AS end_pos,
    h.3 AS category,
    substring(sql, h.1 + 1, h.2 - h.1) AS source
FROM hi
ARRAY JOIN hl AS h
ORDER BY start_pos;

-- ============================================
-- 6. Compare tokenizeQuery vs highlightQuery
-- ============================================

SELECT '========== 6. Same Query, Both Functions ==========';

WITH q AS (SELECT 'SELECT count(*) FROM events WHERE ts > now()' AS sql)
SELECT
    'tokenizeQuery (lexer)'  AS source,
    length(tokenizeQuery(sql))  AS tokens_or_highlights
FROM q
UNION ALL
SELECT
    'highlightQuery (parser)' AS source,
    length(highlightQuery(sql)) AS tokens_or_highlights
FROM q;

-- ============================================
-- 7. Find All Identifiers In a Query Corpus
-- ============================================

SELECT '========== 7. Identifier Extraction From a Query Log ==========';

DROP TABLE IF EXISTS query_log_demo;
CREATE TABLE query_log_demo (id UInt32, q String) ENGINE = MergeTree() ORDER BY id;

INSERT INTO query_log_demo VALUES
    (1, 'SELECT user_id, count() FROM events GROUP BY user_id'),
    (2, 'SELECT * FROM orders WHERE region = ''KR'' AND total > 100'),
    (3, 'SELECT region, sum(revenue) FROM monthly_summary GROUP BY region');

-- Pull every parser-classified "identifier" from each query
SELECT
    id,
    q,
    arrayDistinct(
        arrayMap(
            h -> substring(q, h.1 + 1, h.2 - h.1),
            arrayFilter(h -> h.3 = 'identifier', highlightQuery(q))
        )
    ) AS identifiers
FROM query_log_demo
ORDER BY id;

-- ============================================
-- 8. Keyword Frequency Across Queries
-- ============================================

SELECT '========== 8. Top Keywords in the Query Log ==========';

SELECT
    lowerUTF8(substring(q, h.1 + 1, h.2 - h.1)) AS keyword,
    count() AS uses
FROM query_log_demo
ARRAY JOIN highlightQuery(q) AS h
WHERE h.3 = 'keyword'
GROUP BY keyword
ORDER BY uses DESC, keyword
LIMIT 10;

-- ============================================
-- Cleanup
-- ============================================

-- DROP TABLE IF EXISTS query_log_demo;

SELECT '========== Test Complete ==========';
SELECT 'tokenizeQuery exposes the lexer; highlightQuery exposes the parser. Both unlock SQL introspection from SQL.' AS summary;
