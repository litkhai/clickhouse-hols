-- ClickHouse 26.4: arrayTranspose + arrayAutocorrelation Test
-- New Features:
--   * arrayTranspose(matrix)               — transpose a 2-D array (rows ↔ columns)
--   * arrayAutocorrelation(arr [, max_lag]) — normalized autocorrelation at each lag
-- References:
--   https://github.com/ClickHouse/ClickHouse/pull/101214
--   https://github.com/ClickHouse/ClickHouse/pull/94776

-- ============================================
-- 1. arrayTranspose Basics
-- ============================================

SELECT '========== 1. Basic arrayTranspose ==========';

-- 2×3 matrix → 3×2
SELECT
    [[1, 2, 3], [4, 5, 6]] AS original,
    arrayTranspose([[1, 2, 3], [4, 5, 6]]) AS transposed;

-- 3×3 square
SELECT arrayTranspose([[1, 2, 3], [4, 5, 6], [7, 8, 9]]) AS rotated_3x3;

-- Single row → column vector
SELECT arrayTranspose([[10, 20, 30, 40]]) AS column_vector;

-- ============================================
-- 2. Transpose Round-Trip Identity
-- ============================================

SELECT '========== 2. Transpose Identity: T(T(M)) == M ==========';

WITH [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12]] AS m
SELECT
    m AS original,
    arrayTranspose(arrayTranspose(m)) AS double_transposed,
    m = arrayTranspose(arrayTranspose(m)) AS round_trip_ok;

-- ============================================
-- 3. Pivot Use Case: Rows of Records → Columns of Fields
-- ============================================

SELECT '========== 3. Pivot Sales Data via arrayTranspose ==========';

-- Imagine "sales" returned as rows of [region, units, revenue]
WITH sales_rows AS (
    SELECT [
        ['NA', '100', '50000'],
        ['EU', '80',  '36000'],
        ['AS', '120', '60000'],
        ['SA', '40',  '18000']
    ] AS rows
)
SELECT
    arrayTranspose(rows) AS columns_view,
    arrayTranspose(rows)[1] AS regions,
    arrayTranspose(rows)[2] AS unit_counts,
    arrayTranspose(rows)[3] AS revenues
FROM sales_rows;

-- ============================================
-- 4. arrayAutocorrelation — Detect Periodicity
-- ============================================

SELECT '========== 4. Autocorrelation Basics ==========';

-- Linear ramp: high positive correlation at lag 1, dropping with lag
SELECT
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] AS ramp,
    arrayAutocorrelation([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) AS autocorr;

-- Constant array: any lag → 0 / NaN (no variance)
SELECT arrayAutocorrelation([5, 5, 5, 5, 5, 5, 5, 5]) AS constant_autocorr;

-- Random noise: tiny correlations, near zero (except lag 0 which is always 1)
SELECT
    arrayAutocorrelation(arrayMap(x -> rand(x) / 4294967295.0, range(50))) AS noise_autocorr;

-- ============================================
-- 5. Detecting a Periodic Signal
-- ============================================

SELECT '========== 5. Detecting Period 7 (Weekly Seasonality) ==========';

-- Synthetic weekly-seasonal series: high values on day 0, decreasing through day 6,
-- repeated 4 times = 28 days
WITH weekly AS (
    SELECT arrayMap(
        i -> [100, 90, 70, 50, 60, 80, 95][1 + (i % 7)],
        range(28)
    ) AS series
)
SELECT
    series,
    arrayAutocorrelation(series, 10) AS autocorr_first_10_lags
FROM weekly;

-- Lag 7 should show a strong positive correlation (≈1) — proving period 7

-- ============================================
-- 6. Limited Lag Range
-- ============================================

SELECT '========== 6. Custom max_lag Parameter ==========';

SELECT
    arrayAutocorrelation([1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10])         AS all_lags,
    arrayAutocorrelation([1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10], 3)      AS first_4_lags;

-- ============================================
-- 7. Combined: Transpose + Autocorrelation
-- ============================================

SELECT '========== 7. Autocorrelation per Column After Transpose ==========';

-- Three signals stacked as rows; compute autocorrelation on each via transpose
WITH stack AS (
    SELECT [
        [1, 2, 3, 4, 5, 6, 7, 8],          -- linear
        [1, -1, 1, -1, 1, -1, 1, -1],      -- alternating
        [5, 5, 5, 5, 5, 5, 5, 5]           -- constant
    ] AS m
)
SELECT
    arrayMap(row -> arrayAutocorrelation(row, 3), m) AS autocorr_per_signal
FROM stack;

-- ============================================
-- Cleanup
-- ============================================

SELECT '========== Test Complete ==========';
SELECT 'arrayTranspose pivots matrices; arrayAutocorrelation detects periodicity.' AS summary;
