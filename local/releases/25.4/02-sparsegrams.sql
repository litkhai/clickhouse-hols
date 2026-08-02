-- ClickHouse 25.4: sparseGrams Test
-- New Features: sparseGrams, sparseGramsHashes and their UTF8 variants; plus
--               hasAll() now using tokenbf_v1 and ngrambf_v1 skip indices.
-- Reference: https://clickhouse.com/docs/whats-new/changelog (25.4, #78176, #77662)

-- Fixed-length n-grams force a choice: short ones are noisy, long ones miss
-- matches. sparseGrams picks boundaries from the data itself, producing grams
-- of varying length that line up across similar strings.

-- ============================================
-- 1. What sparseGrams Produces
-- ============================================

SELECT '========== 1. sparseGrams on a Short String ==========';

SELECT
    sparseGrams('hello world')          AS grams,
    length(sparseGrams('hello world'))  AS gram_count;

-- ============================================
-- 2. Compared With Fixed n-grams
-- ============================================

SELECT '========== 2. Fixed ngrams vs sparseGrams ==========';

SELECT
    ngrams('hello world', 3)              AS fixed_3,
    length(ngrams('hello world', 3))      AS fixed_count,
    length(sparseGrams('hello world'))    AS sparse_count;

-- The grams sparseGrams emits vary in length, which is the point.
SELECT
    arraySort(arrayMap(g -> length(g), sparseGrams('hello world'))) AS gram_lengths;

-- ============================================
-- 3. The Hashed Form
-- ============================================

SELECT '========== 3. sparseGramsHashes ==========';

-- The hashed variant is what an index or a similarity join wants: fixed-width
-- integers instead of substrings.
SELECT
    sparseGramsHashes('hello world')          AS hashes,
    length(sparseGramsHashes('hello world'))  AS hash_count;

-- Same string, same hashes.
SELECT
    sparseGramsHashes('hello world') = sparseGramsHashes('hello world') AS deterministic;

-- ============================================
-- 4. UTF-8 Variants
-- ============================================

SELECT '========== 4. sparseGramsUTF8 ==========';

-- The plain functions work on bytes; the UTF8 variants work on characters,
-- which matters for any non-ASCII text.
SELECT
    length(sparseGrams('안녕하세요 클릭하우스'))     AS byte_grams,
    length(sparseGramsUTF8('안녕하세요 클릭하우스')) AS char_grams;

SELECT sparseGramsUTF8('클릭하우스') AS korean_grams;

-- ============================================
-- 5. Near-Duplicate Detection
-- ============================================

SELECT '========== 5. Shared Grams Between Similar Strings ==========';

DROP TABLE IF EXISTS docs;

CREATE TABLE docs (id UInt32, body String) ENGINE = MergeTree ORDER BY id;

INSERT INTO docs VALUES
    (1, 'the quick brown fox jumps over the lazy dog'),
    (2, 'the quick brown fox jumped over the lazy dog'),
    (3, 'a completely unrelated sentence about databases');

SELECT
    a.id AS doc_a,
    b.id AS doc_b,
    length(arrayIntersect(sparseGramsHashes(a.body), sparseGramsHashes(b.body))) AS shared_grams
FROM docs AS a
CROSS JOIN docs AS b
WHERE a.id < b.id
ORDER BY shared_grams DESC;

-- ============================================
-- 6. A Jaccard-Style Similarity
-- ============================================

SELECT '========== 6. Similarity From Gram Overlap ==========';

SELECT
    a.id AS doc_a,
    b.id AS doc_b,
    round(
        length(arrayIntersect(sparseGramsHashes(a.body), sparseGramsHashes(b.body)))
        / length(arrayDistinct(arrayConcat(sparseGramsHashes(a.body), sparseGramsHashes(b.body)))),
        3
    ) AS jaccard
FROM docs AS a
CROSS JOIN docs AS b
WHERE a.id < b.id
ORDER BY jaccard DESC;

-- ============================================
-- 7. hasAll Using a Token Index
-- ============================================

SELECT '========== 7. hasAll With tokenbf_v1 ==========';

DROP TABLE IF EXISTS tagged;

CREATE TABLE tagged
(
    id   UInt64,
    tags Array(String),
    INDEX idx_tags tags TYPE tokenbf_v1(4096, 3, 0) GRANULARITY 1
)
ENGINE = MergeTree
ORDER BY id;

-- topic_/owner_ cycle across every granule, while 'incident' is confined to a
-- narrow id range. Only the clustered tag gives the index something to skip.
INSERT INTO tagged
SELECT
    number,
    arrayConcat(
        [concat('topic_', toString(number % 100)), concat('owner_', toString(number % 7))],
        if(number BETWEEN 150000 AND 150200, ['incident'], [])
    )
FROM numbers(200000);

SELECT
    countIf(hasAll(tags, ['topic_42'])) AS spread_tag_rows,
    countIf(hasAll(tags, ['incident'])) AS clustered_tag_rows
FROM tagged;

-- ============================================
-- 8. The Index Engaging
-- ============================================

SELECT '========== 8. Granules Skipped by the Token Index ==========';

-- 25.4 taught hasAll() to consult tokenbf_v1 and ngrambf_v1. Whether that
-- prunes depends on the data: a tag present in every granule cannot be skipped.
SELECT 'spread tag - index consulted, nothing to skip' AS scenario;
EXPLAIN indexes = 1
SELECT count() FROM tagged WHERE hasAll(tags, ['topic_42', 'owner_0']);

SELECT 'clustered tag - most granules skipped' AS scenario;
EXPLAIN indexes = 1
SELECT count() FROM tagged WHERE hasAll(tags, ['incident']);

-- ============================================
-- 9. Correctness With and Without the Index
-- ============================================

SELECT '========== 9. Same Answer Either Way ==========';

SELECT
    (SELECT count() FROM tagged WHERE hasAll(tags, ['incident'])) AS with_index,
    (SELECT count() FROM tagged WHERE hasAll(tags, ['incident'])
        SETTINGS use_skip_indexes = 0) AS without_index,
    with_index = without_index AS identical;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS docs;
-- DROP TABLE IF EXISTS tagged;

SELECT '========== Test Complete ==========';
SELECT 'sparseGrams derives gram boundaries from the data instead of a fixed n.' AS summary;
