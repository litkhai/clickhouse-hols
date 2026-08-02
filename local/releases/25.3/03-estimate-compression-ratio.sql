-- ClickHouse 25.3 LTS: estimateCompressionRatio Test
-- New Feature: an aggregate function that estimates how well a column would
--              compress, optionally under a named codec, without writing it.
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- Choosing a codec normally means writing the data several ways and comparing
-- part sizes. estimateCompressionRatio answers the same question from a SELECT.

-- ============================================
-- 1. Columns With Very Different Compressibility
-- ============================================

SELECT '========== 1. Test Data ==========';

DROP TABLE IF EXISTS compression_demo;

CREATE TABLE compression_demo
(
    id           UInt64,
    constant     String,
    low_card     String,
    incrementing UInt64,
    random_ish   UInt64,
    timestamp    DateTime
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO compression_demo
SELECT
    number,
    'the same value in every row',
    ['alpha', 'beta', 'gamma', 'delta'][number % 4 + 1],
    number,
    cityHash64(number),
    toDateTime('2025-03-20 00:00:00') + number
FROM numbers(500000);

SELECT count() AS rows FROM compression_demo;

-- ============================================
-- 2. The Estimate, Column by Column
-- ============================================

SELECT '========== 2. Default Codec Ratios ==========';

-- Higher is better: the estimated uncompressed-to-compressed ratio.
SELECT
    round(estimateCompressionRatio(constant), 1)     AS constant_col,
    round(estimateCompressionRatio(low_card), 1)     AS low_cardinality,
    round(estimateCompressionRatio(incrementing), 1) AS incrementing,
    round(estimateCompressionRatio(random_ish), 1)   AS random_ish
FROM compression_demo;

-- ============================================
-- 3. Naming a Codec
-- ============================================

SELECT '========== 3. Comparing Codecs on One Column ==========';

-- The parametric form takes the codec to simulate.
SELECT
    round(estimateCompressionRatio('LZ4')(low_card), 1)  AS lz4,
    round(estimateCompressionRatio('ZSTD')(low_card), 1) AS zstd,
    round(estimateCompressionRatio('ZSTD(9)')(low_card), 1) AS zstd_9
FROM compression_demo;

-- ============================================
-- 4. Picking a Codec for a Numeric Column
-- ============================================

SELECT '========== 4. Delta and DoubleDelta on Sequences ==========';

-- An incrementing column is the case Delta codecs exist for.
SELECT
    round(estimateCompressionRatio('ZSTD')(incrementing), 1)              AS zstd_only,
    round(estimateCompressionRatio('Delta, ZSTD')(incrementing), 1)       AS delta_zstd,
    round(estimateCompressionRatio('DoubleDelta, ZSTD')(incrementing), 1) AS doubledelta_zstd
FROM compression_demo;

-- ============================================
-- 5. The Same Codecs Where They Do Not Apply
-- ============================================

SELECT '========== 5. Delta on Non-Sequential Data ==========';

-- Delta on a hash column has nothing to exploit, and can make things worse.
SELECT
    round(estimateCompressionRatio('ZSTD')(random_ish), 1)        AS zstd_only,
    round(estimateCompressionRatio('Delta, ZSTD')(random_ish), 1) AS delta_zstd
FROM compression_demo;

-- ============================================
-- 6. Timestamps
-- ============================================

SELECT '========== 6. A Monotonic DateTime Column ==========';

SELECT
    round(estimateCompressionRatio('ZSTD')(timestamp), 1)              AS zstd,
    round(estimateCompressionRatio('Delta, ZSTD')(timestamp), 1)       AS delta_zstd,
    round(estimateCompressionRatio('DoubleDelta, ZSTD')(timestamp), 1) AS doubledelta_zstd
FROM compression_demo;

-- ============================================
-- 7. Estimate Versus Reality
-- ============================================

SELECT '========== 7. Checking the Estimate Against a Real Part ==========';

DROP TABLE IF EXISTS compression_real;

CREATE TABLE compression_real
(
    id           UInt64,
    incrementing UInt64 CODEC(Delta, ZSTD)
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO compression_real SELECT number, number FROM numbers(500000);

SELECT
    column,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    formatReadableSize(sum(data_compressed_bytes))   AS compressed,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 1) AS actual_ratio
FROM system.parts_columns
WHERE table = 'compression_real' AND active AND column = 'incrementing'
GROUP BY column;

-- ============================================
-- 8. Ranking Every Column at Once
-- ============================================

SELECT '========== 8. Which Column Is Worth a Codec ==========';

SELECT column_name, ratio
FROM
(
    SELECT 'constant' AS column_name, round(estimateCompressionRatio(constant), 1) AS ratio FROM compression_demo
    UNION ALL
    SELECT 'low_card',     round(estimateCompressionRatio(low_card), 1)     FROM compression_demo
    UNION ALL
    SELECT 'incrementing', round(estimateCompressionRatio(incrementing), 1) FROM compression_demo
    UNION ALL
    SELECT 'random_ish',   round(estimateCompressionRatio(random_ish), 1)   FROM compression_demo
)
ORDER BY ratio DESC;

-- ============================================
-- 9. Sampling for a Faster Estimate
-- ============================================

SELECT '========== 9. Estimating From a Sample ==========';

-- On a large table the estimate can run over a subset; the ratio is stable
-- enough for a codec decision.
SELECT
    round(estimateCompressionRatio('ZSTD')(incrementing), 1) AS from_all_rows
FROM compression_demo;

SELECT
    round(estimateCompressionRatio('ZSTD')(incrementing), 1) AS from_50k_rows
FROM (SELECT incrementing FROM compression_demo LIMIT 50000);

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS compression_demo;
-- DROP TABLE IF EXISTS compression_real;

SELECT '========== Test Complete ==========';
SELECT 'Codec selection becomes a SELECT instead of a write-and-measure loop.' AS summary;
