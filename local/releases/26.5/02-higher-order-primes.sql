-- ClickHouse 26.5: Bare Function Names in Higher-Order Functions + isPrime / isProbablePrime
-- New Features:
--   * Higher-order functions (arrayMap, arrayFilter, etc.) accept bare function names
--     e.g. arrayMap(negate, [1,2,3]) instead of arrayMap(x -> negate(x), [1,2,3])
--   * isPrime(n)         — exact primality test (UInt64)
--   * isProbablePrime(n [, rounds]) — Miller-Rabin probabilistic test (UInt128 / UInt256)
-- References:
--   https://github.com/ClickHouse/ClickHouse/pull/101033
--   https://github.com/ClickHouse/ClickHouse/pull/104234

-- ============================================
-- 1. Bare Function Names — Old vs New Syntax
-- ============================================

SELECT '========== 1. arrayMap with a Bare Function Name ==========';

-- Old (still works): explicit lambda
SELECT arrayMap(x -> negate(x), [1, 2, 3, 4, 5]) AS old_syntax;

-- New: pass the function by name directly
SELECT arrayMap(negate, [1, 2, 3, 4, 5]) AS new_syntax;

-- They produce identical output
SELECT arrayMap(x -> negate(x), [1, 2, 3, 4, 5])
     = arrayMap(negate, [1, 2, 3, 4, 5]) AS results_equal;

-- ============================================
-- 2. arrayFilter with Bare Function Names
-- ============================================

SELECT '========== 2. arrayFilter with Bare Predicates ==========';

-- Filter for even numbers
SELECT arrayFilter(x -> NOT (x % 2), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) AS evens;

-- Filter for primes — passing isPrime directly
SELECT arrayFilter(isPrime, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]) AS primes_only;

-- ============================================
-- 3. isPrime — Exact Primality Test
-- ============================================

SELECT '========== 3. isPrime (exact, UInt64) ==========';

SELECT
    n,
    isPrime(n) AS is_prime
FROM (SELECT number AS n FROM numbers(2, 20))
ORDER BY n;

-- Find all primes below 50 by filtering numbers()
SELECT groupArray(n) AS primes_below_50
FROM (
    SELECT number AS n
    FROM numbers(2, 49)
    WHERE isPrime(n)
);

-- ============================================
-- 4. isProbablePrime — Wider Types
-- ============================================

SELECT '========== 4. isProbablePrime (Miller-Rabin, up to UInt256) ==========';

-- Test some known small primes via UInt128
SELECT
    n,
    isProbablePrime(toUInt128(n)) AS is_probable_prime
FROM (SELECT arrayJoin([2, 3, 4, 5, 17, 100, 2147483647]) AS n);

-- 2^61 - 1 (Mersenne prime, fits in UInt64)
SELECT
    toUInt128(2305843009213693951) AS mersenne_61_minus_1,
    isProbablePrime(toUInt128(2305843009213693951)) AS is_prime;

-- A composite UInt128 value
SELECT
    toUInt128('340282366920938463463374607431768211455') AS uint128_max,
    isProbablePrime(toUInt128('340282366920938463463374607431768211455')) AS is_prime;

-- ============================================
-- 5. Configurable Rounds for Confidence
-- ============================================

SELECT '========== 5. isProbablePrime with Custom Rounds ==========';

-- Default rounds = 25 (FP probability < 10^-15)
-- More rounds = even more confidence
SELECT
    n,
    isProbablePrime(toUInt128(n))      AS default_25_rounds,
    isProbablePrime(toUInt128(n), 5)   AS rounds_5,
    isProbablePrime(toUInt128(n), 100) AS rounds_100
FROM (SELECT arrayJoin([2, 3, 17, 97, 2305843009213693951]) AS n);

-- ============================================
-- 6. Higher-Order Functions + Primality
-- ============================================

SELECT '========== 6. arrayCount with isPrime ==========';

-- Count primes in the first 100 natural numbers
SELECT arrayCount(isPrime, range(2, 100)) AS primes_below_100;

-- Sum of primes below 100
SELECT arraySum(arrayFilter(isPrime, range(2, 100))) AS sum_of_primes_below_100;

-- ============================================
-- 7. Cross-Tabulation: Bare Function Variants
-- ============================================

SELECT '========== 7. Comparison of Bare Function Usage ==========';

WITH samples AS (
    SELECT range(1, 11) AS xs   -- [1..10]
)
SELECT
    arrayMap(negate,        xs) AS negated,
    arrayMap(abs,           arrayMap(negate, xs)) AS reabsoluted,
    arrayMap(toString,      xs) AS as_strings,
    arrayFilter(isFinite,   arrayMap(x -> x / 2.0, xs)) AS finite_halves
FROM samples;

-- ============================================
-- 8. Mixed: Lambda + Bare Function
-- ============================================

SELECT '========== 8. Lambda Calling a Bare Function ==========';

-- Pairs (n, isPrime(n)) via lambda
SELECT
    arrayMap(n -> (n, isPrime(n)), range(2, 12)) AS pairs;

-- Sum of squares of primes (uses bare isPrime + explicit lambda for x*x)
SELECT
    arraySum(arrayMap(x -> x * x, arrayFilter(isPrime, range(2, 20)))) AS sum_of_squared_primes;

-- ============================================
-- Cleanup
-- ============================================

SELECT '========== Test Complete ==========';
SELECT 'Bare function names cut lambda boilerplate; isPrime + isProbablePrime add number-theory primitives.' AS summary;
