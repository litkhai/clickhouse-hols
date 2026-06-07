-- ClickHouse 26.2: primes Table Function & system.primes Test
-- New Feature: Table function `primes(n)` and `system.primes` system table providing prime numbers
-- Reference: https://github.com/ClickHouse/ClickHouse/pull/92776

-- ============================================
-- 1. Basic Usage of system.primes
-- ============================================

SELECT '========== 1. system.primes System Table ==========';

-- Schema of system.primes
DESCRIBE system.primes;

-- First 10 prime numbers
SELECT prime
FROM system.primes
LIMIT 10;

-- Count primes below 100
SELECT count() AS primes_under_100
FROM system.primes
WHERE prime < 100;

-- ============================================
-- 2. primes() Table Function
-- ============================================

SELECT '========== 2. primes() Table Function ==========';

-- Generate the first 20 primes
SELECT prime
FROM primes(20);

-- Sum of the first 100 primes
SELECT sum(prime) AS sum_first_100_primes
FROM primes(100);

-- ============================================
-- 3. Prime Number Analysis
-- ============================================

SELECT '========== 3. Twin Primes (differ by 2) ==========';

-- Find twin prime pairs in the first 200 primes
WITH ordered AS (
    SELECT prime AS p, rowNumberInAllBlocks() AS rn
    FROM primes(200)
)
SELECT
    a.p AS p1,
    b.p AS p2,
    b.p - a.p AS gap
FROM ordered AS a
INNER JOIN ordered AS b ON b.rn = a.rn + 1
WHERE b.p - a.p = 2
ORDER BY a.p
LIMIT 20;

-- ============================================
-- 4. Prime Gap Distribution
-- ============================================

SELECT '========== 4. Prime Gap Distribution (first 500 primes) ==========';

WITH ordered AS (
    SELECT prime AS p, rowNumberInAllBlocks() AS rn
    FROM primes(500)
)
SELECT
    b.p - a.p AS gap,
    count() AS occurrences
FROM ordered AS a
INNER JOIN ordered AS b ON b.rn = a.rn + 1
GROUP BY gap
ORDER BY gap;

-- ============================================
-- 5. Sieve-style Composite Check via JOIN
-- ============================================

SELECT '========== 5. Composite Numbers Identified ==========';

-- Numbers between 2 and 30 that are NOT prime
SELECT n AS composite
FROM (SELECT number AS n FROM numbers(2, 29)) AS candidates
WHERE n NOT IN (SELECT prime FROM primes(100))
ORDER BY n;

-- ============================================
-- 6. Building a Prime Lookup Table
-- ============================================

SELECT '========== 6. Materialized Prime Cache Table ==========';

DROP TABLE IF EXISTS prime_cache;
CREATE TABLE prime_cache
(
    prime UInt64,
    ordinal UInt64
) ENGINE = MergeTree()
ORDER BY prime;

-- Cache the first 1000 primes
INSERT INTO prime_cache
SELECT prime, rowNumberInAllBlocks() + 1 AS ordinal
FROM primes(1000);

-- Quick prime-rank lookup
SELECT ordinal, prime
FROM prime_cache
WHERE prime IN (2, 17, 101, 7919)
ORDER BY ordinal;

-- ============================================
-- 7. Practical Use: Hash Bucket Sizing
-- ============================================

SELECT '========== 7. Nearest Prime ≥ N (for hash table sizing) ==========';

-- For each target capacity, find the smallest prime >= target
WITH targets AS (
    SELECT arrayJoin([10, 50, 100, 500, 1000]) AS target
)
SELECT
    target,
    (SELECT min(prime) FROM primes(2000) WHERE prime >= target) AS nearest_prime_ge
FROM targets
ORDER BY target;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS prime_cache;

SELECT '========== Test Complete ==========';
SELECT 'primes() table function and system.primes simplify number-theory queries!' AS summary;
