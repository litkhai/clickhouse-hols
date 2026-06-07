-- ClickHouse 26.3 LTS: Unicode Normalization Functions Test
-- New Features:
--   * caseFoldUTF8(s)             — locale-independent Unicode case folding
--   * removeDiacriticsUTF8(s)     — strip accents / combining marks
--   * normalizeUTF8NFKCCasefold(s) — NFKC normalization + case folding (single pass)
-- References:
--   https://github.com/ClickHouse/ClickHouse/pull/98973
--   https://github.com/ClickHouse/ClickHouse/pull/99276

-- ============================================
-- 1. caseFoldUTF8 — Beyond ASCII lower()
-- ============================================

SELECT '========== 1. caseFoldUTF8 vs lower ==========';

-- Plain lower() handles ASCII but not all Unicode cases consistently.
-- caseFoldUTF8 applies Unicode case folding rules.

SELECT
    s,
    lower(s)         AS lowered,
    caseFoldUTF8(s)  AS folded
FROM (
    SELECT arrayJoin([
        'HELLO World',
        'ÄÖÜ',
        'Straße',          -- German sharp s
        'İSTANBUL',        -- Turkish dotted I
        'GROẞ',            -- Capital sharp s (since Unicode 5.1)
        'Café',
        'ΕΛΛΑΣ'            -- Greek
    ]) AS s
);

-- ============================================
-- 2. removeDiacriticsUTF8 — Accent Stripping
-- ============================================

SELECT '========== 2. removeDiacriticsUTF8 ==========';

SELECT
    s,
    removeDiacriticsUTF8(s) AS stripped
FROM (
    SELECT arrayJoin([
        'naïve café résumé',
        'crème brûlée',
        'jalapeño',
        'Pokémon',
        'Český jazyk',
        'Đorđe',
        'Łódź'
    ]) AS s
);

-- ============================================
-- 3. normalizeUTF8NFKCCasefold — Search-Ready Key
-- ============================================

SELECT '========== 3. normalizeUTF8NFKCCasefold ==========';

-- NFKC compatibility normalization (e.g. full-width → half-width, ligatures → ascii)
-- combined with case folding, in one operation.

SELECT
    s,
    normalizeUTF8NFKCCasefold(s) AS normalized
FROM (
    SELECT arrayJoin([
        'ＡＢＣ',            -- full-width Latin
        'ﬁnale',            -- ligature fi
        'Hello World',
        'CAFÉ',
        '①②③',            -- circled digits
        '㎏',               -- compatibility character for "kg"
        'Ⅷ'                -- Roman numeral VIII
    ]) AS s
);

-- ============================================
-- 4. Combined Pipeline: Search-Friendly Index Column
-- ============================================

SELECT '========== 4. Searchable Name Column ==========';

DROP TABLE IF EXISTS people;
CREATE TABLE people (
    id UInt32,
    full_name String,
    -- search_key is fully normalized: NFKC + case-folded + diacritics removed
    search_key String MATERIALIZED removeDiacriticsUTF8(normalizeUTF8NFKCCasefold(full_name))
) ENGINE = MergeTree() ORDER BY id;

INSERT INTO people (id, full_name) VALUES
    (1, 'José García'),
    (2, 'Jose Garcia'),
    (3, 'JOSÉ GARCÍA'),
    (4, 'Łukasz Wójcik'),
    (5, 'Lukasz Wojcik'),
    (6, 'Müller'),
    (7, 'MUELLER'),
    (8, 'mueller'),
    (9, 'Smith'),
    (10,'François Renoir');

-- All variants of "Jose Garcia" collapse to the same search key
SELECT id, full_name, search_key
FROM people
ORDER BY search_key, id;

-- One query matches every spelling
SELECT id, full_name
FROM people
WHERE search_key = removeDiacriticsUTF8(normalizeUTF8NFKCCasefold('josé garcía'))
ORDER BY id;

-- ============================================
-- 5. Group-By on Folded Key for Duplicate Detection
-- ============================================

SELECT '========== 5. Detecting Equivalent Names ==========';

SELECT
    search_key,
    count() AS variants,
    groupArray(full_name) AS spellings
FROM people
GROUP BY search_key
HAVING variants > 1
ORDER BY search_key;

-- ============================================
-- 6. Comparison Table of the Three Functions
-- ============================================

SELECT '========== 6. Side-by-Side: All Three Functions ==========';

WITH samples AS (
    SELECT arrayJoin(['CAFÉ', 'Straße', 'İSTANBUL', 'naïve', 'ＡＢＣ', '㎏']) AS s
)
SELECT
    s,
    caseFoldUTF8(s)              AS case_folded,
    removeDiacriticsUTF8(s)      AS no_diacritics,
    normalizeUTF8NFKCCasefold(s) AS nfkc_casefolded
FROM samples;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS people;

SELECT '========== Test Complete ==========';
SELECT 'Unicode normalization functions enable robust, language-aware text matching.' AS summary;
