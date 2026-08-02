-- ClickHouse 25.4: Array Distance and Similarity Functions Test
-- New Features: arrayLevenshteinDistance, arrayLevenshteinDistanceWeighted,
--               arraySimilarity
-- Reference: https://clickhouse.com/docs/whats-new/changelog (25.4, #77187)

-- Levenshtein distance is normally defined over characters. These functions
-- lift it to arrays, so the unit of edit is an array element — a page in a
-- session, a step in a pipeline, a token in a sequence.

-- ============================================
-- 1. The Basic Distance
-- ============================================

SELECT '========== 1. arrayLevenshteinDistance ==========';

-- One substitution: b -> x
SELECT
    arrayLevenshteinDistance(['a', 'b', 'c'], ['a', 'x', 'c']) AS one_substitution,
    arrayLevenshteinDistance(['a', 'b', 'c'], ['a', 'b', 'c']) AS identical,
    arrayLevenshteinDistance(['a', 'b', 'c'], [])              AS delete_everything,
    arrayLevenshteinDistance(['a'], ['a', 'b', 'c'])           AS two_insertions;

-- ============================================
-- 2. It Is Element-Wise, Not Character-Wise
-- ============================================

SELECT '========== 2. Elements Are Atomic ==========';

-- 'checkout' and 'checkout_v2' differ by three characters but count as one
-- element substitution: the function never looks inside an element.
SELECT
    arrayLevenshteinDistance(['home', 'checkout'], ['home', 'checkout_v2']) AS array_distance,
    editDistance('checkout', 'checkout_v2')                                 AS string_distance;

-- ============================================
-- 3. Comparing User Journeys
-- ============================================

SELECT '========== 3. Session Path Distance ==========';

DROP TABLE IF EXISTS sessions;

CREATE TABLE sessions (session_id UInt32, path Array(String))
ENGINE = MergeTree ORDER BY session_id;

INSERT INTO sessions VALUES
    (1, ['home', 'search', 'product', 'cart', 'checkout']),
    (2, ['home', 'search', 'product', 'cart', 'checkout']),
    (3, ['home', 'product', 'cart', 'checkout']),
    (4, ['home', 'search', 'product']),
    (5, ['home', 'blog', 'blog', 'home']);

-- Distance of every session from the canonical happy path.
SELECT
    session_id,
    path,
    arrayLevenshteinDistance(path, ['home', 'search', 'product', 'cart', 'checkout']) AS edits_from_happy_path
FROM sessions
ORDER BY edits_from_happy_path, session_id;

-- ============================================
-- 4. Clustering by Distance
-- ============================================

SELECT '========== 4. Grouping Near-Identical Journeys ==========';

SELECT
    arrayLevenshteinDistance(a.path, b.path) AS distance,
    count()                                  AS pairs
FROM sessions AS a
CROSS JOIN sessions AS b
WHERE a.session_id < b.session_id
GROUP BY distance
ORDER BY distance;

-- ============================================
-- 5. Weighted Distance
-- ============================================

SELECT '========== 5. arrayLevenshteinDistanceWeighted ==========';

-- Each element carries a weight, so editing an important element costs more.
-- Signature: (lhs, rhs, lhs_weights, rhs_weights)
SELECT
    arrayLevenshteinDistanceWeighted(
        ['a', 'b', 'c'], ['a', 'x', 'c'],
        [1.0, 2.0, 3.0], [1.0, 5.0, 3.0]
    ) AS weighted_substitution,
    arrayLevenshteinDistance(['a', 'b', 'c'], ['a', 'x', 'c']) AS unweighted;

-- ============================================
-- 6. Weighting the Steps That Matter
-- ============================================

SELECT '========== 6. Checkout Costs More Than a Blog Visit ==========';

-- Dropping 'checkout' should count for more than dropping 'blog'.
SELECT
    'lost checkout' AS scenario,
    arrayLevenshteinDistanceWeighted(
        ['home', 'product', 'checkout'], ['home', 'product'],
        [1.0, 2.0, 10.0],                [1.0, 2.0]
    ) AS weighted_distance
UNION ALL
SELECT
    'lost blog visit',
    arrayLevenshteinDistanceWeighted(
        ['home', 'product', 'blog'], ['home', 'product'],
        [1.0, 2.0, 1.0],             [1.0, 2.0]
    );

-- ============================================
-- 7. arraySimilarity
-- ============================================

SELECT '========== 7. arraySimilarity ==========';

-- Normalises the weighted distance into 0..1, where 1 is identical.
SELECT
    arraySimilarity(['a', 'b', 'c'], ['a', 'b', 'c'], [1.0, 1.0, 1.0], [1.0, 1.0, 1.0]) AS identical,
    arraySimilarity(['a', 'b', 'c'], ['a', 'x', 'c'], [1.0, 2.0, 3.0], [1.0, 5.0, 3.0]) AS one_edit,
    arraySimilarity(['a', 'b'],      ['x', 'y'],      [1.0, 1.0],      [1.0, 1.0])      AS nothing_in_common;

-- ============================================
-- 8. Ranking Sessions by Similarity
-- ============================================

SELECT '========== 8. Closest Journeys to the Happy Path ==========';

SELECT
    session_id,
    path,
    round(arraySimilarity(
        path,
        ['home', 'search', 'product', 'cart', 'checkout'],
        arrayMap(x -> 1.0, path),
        [1.0, 1.0, 1.0, 1.0, 1.0]
    ), 3) AS similarity
FROM sessions
ORDER BY similarity DESC, session_id;

-- ============================================
-- 9. Weights Must Line Up With Elements
-- ============================================

SELECT '========== 9. Weight Arrays Match Their Value Arrays ==========';

-- Building weights with arrayMap keeps the lengths in step, which matters when
-- the arrays come from a column rather than a literal.
SELECT
    session_id,
    length(path)                       AS steps,
    length(arrayMap(x -> 1.0, path))   AS weights,
    steps = weights                    AS aligned
FROM sessions
ORDER BY session_id;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS sessions;

SELECT '========== Test Complete ==========';
SELECT 'Levenshtein over array elements, with weights when some steps matter more.' AS summary;
