-- ClickHouse 25.3 LTS: New Functions Test
-- New Features: arraySymmetricDifference, keccak256, firstNonDefault,
--               compareSubstrings, icebergTruncate, toYearNumSinceEpoch,
--               toMonthNumSinceEpoch
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- Confirmed by diffing system.functions between 25.2 and 25.3, so this is the
-- function surface the release actually added.

-- ============================================
-- 1. arraySymmetricDifference
-- ============================================

SELECT '========== 1. arraySymmetricDifference ==========';

-- Elements that do not occur in *all* of the arguments. With two arrays that
-- is the familiar symmetric difference.
SELECT
    arraySymmetricDifference([1, 2, 3], [3, 4, 5]) AS two_arrays,
    arraySymmetricDifference([1, 2], [2, 3], [3, 4]) AS three_arrays;

-- Order is not guaranteed, so sort when comparing results.
SELECT arraySort(arraySymmetricDifference([1, 2, 3], [3, 4, 5])) AS sorted;

-- ============================================
-- 2. Comparing With the Other Array Set Functions
-- ============================================

SELECT '========== 2. Against Intersect and Concat ==========';

SELECT
    arraySort(arrayIntersect([1, 2, 3], [3, 4, 5]))            AS in_both,
    arraySort(arraySymmetricDifference([1, 2, 3], [3, 4, 5]))  AS in_exactly_one,
    arraySort(arrayDistinct(arrayConcat([1, 2, 3], [3, 4, 5]))) AS in_either;

-- ============================================
-- 3. A Practical Use: Permission Drift
-- ============================================

SELECT '========== 3. Which Permissions Differ ==========';

DROP TABLE IF EXISTS role_grants;

CREATE TABLE role_grants (role String, granted Array(String))
ENGINE = MergeTree ORDER BY role;

INSERT INTO role_grants VALUES
    ('analyst',  ['select', 'show', 'dictget']),
    ('engineer', ['select', 'show', 'insert', 'alter']);

SELECT
    arraySort(arraySymmetricDifference(
        (SELECT granted FROM role_grants WHERE role = 'analyst'),
        (SELECT granted FROM role_grants WHERE role = 'engineer')
    )) AS only_one_role_has_these;

-- ============================================
-- 4. keccak256
-- ============================================

SELECT '========== 4. keccak256 ==========';

-- The hash Ethereum and other chains use for addresses and event topics.
-- Note this is Keccak-256, not the finalised SHA3-256: the two differ.
SELECT
    hex(keccak256('hello'))  AS hello_hash,
    length(keccak256('hello')) AS bytes;

SELECT
    hex(keccak256(''))       AS empty_hash;

-- ============================================
-- 5. Hashing a Column
-- ============================================

SELECT '========== 5. keccak256 Over Rows ==========';

DROP TABLE IF EXISTS wallets;

CREATE TABLE wallets (id UInt32, label String) ENGINE = MergeTree ORDER BY id;
INSERT INTO wallets VALUES (1, 'treasury'), (2, 'payroll'), (3, 'treasury');

SELECT
    id,
    label,
    lower(hex(keccak256(label))) AS label_hash
FROM wallets
ORDER BY id;

-- Equal inputs hash equal, which is what makes it usable as a grouping key.
SELECT
    lower(hex(keccak256(label))) AS label_hash,
    count()                      AS occurrences,
    groupArray(id)               AS ids
FROM wallets
GROUP BY label_hash
ORDER BY occurrences DESC;

-- ============================================
-- 6. firstNonDefault
-- ============================================

SELECT '========== 6. firstNonDefault ==========';

-- Returns the first argument that is not its type's default value. It is the
-- COALESCE of "empty means missing" data, where 0 and '' stand in for NULL.
SELECT
    firstNonDefault(0, 0, 42, 7)        AS first_nonzero,
    firstNonDefault('', '', 'found')    AS first_nonempty,
    firstNonDefault(0, 0, 0)            AS all_defaults;

-- ============================================
-- 7. A Fallback Chain
-- ============================================

SELECT '========== 7. Picking the First Populated Column ==========';

DROP TABLE IF EXISTS contacts;

CREATE TABLE contacts (id UInt32, mobile String, work String, home String)
ENGINE = MergeTree ORDER BY id;

INSERT INTO contacts VALUES
    (1, '010-1111', '02-2222', '02-3333'),
    (2, '',         '02-4444', '02-5555'),
    (3, '',         '',        '02-6666'),
    (4, '',         '',        '');

SELECT
    id,
    firstNonDefault(mobile, work, home) AS best_number,
    best_number = '' AS no_number_at_all
FROM contacts
ORDER BY id;

-- ============================================
-- 8. compareSubstrings
-- ============================================

SELECT '========== 8. compareSubstrings ==========';

-- Three-way comparison of a slice of each string, without materialising the
-- substrings: compareSubstrings(haystack1, haystack2, offset1, offset2, length)
SELECT
    compareSubstrings('abcdef', 'abcxyz', 0, 0, 3) AS first_three_equal,
    compareSubstrings('abcdef', 'abcxyz', 3, 3, 3) AS last_three_differ,
    compareSubstrings('zebra',  'apple',  0, 0, 1) AS z_after_a;

-- ============================================
-- 9. Iceberg Partition Transform Helpers
-- ============================================

SELECT '========== 9. Iceberg Time and Truncate Transforms ==========';

-- These mirror the Iceberg partition transforms, so a ClickHouse query can
-- compute the same partition value the table was written with.
SELECT
    toYearNumSinceEpoch(toDate('2025-03-20'))  AS years_since_1970,
    toMonthNumSinceEpoch(toDate('2025-03-20')) AS months_since_1970,
    icebergTruncate(10, 123)                   AS truncated_to_10,
    icebergTruncate(100, 1234)                 AS truncated_to_100;

-- ============================================
-- 10. Bucketing a Date Column the Iceberg Way
-- ============================================

SELECT '========== 10. Month Partitions ==========';

SELECT
    d,
    toMonthNumSinceEpoch(d) AS month_partition,
    count()                 AS rows
FROM
(
    SELECT toDate('2025-01-01') + (number * 15) AS d
    FROM numbers(8)
)
GROUP BY d, month_partition
ORDER BY d;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS role_grants;
-- DROP TABLE IF EXISTS wallets;
-- DROP TABLE IF EXISTS contacts;

SELECT '========== Test Complete ==========';
SELECT 'Symmetric difference, Keccak-256 and default-aware fallbacks, all in SQL.' AS summary;
