-- ClickHouse 26.3 LTS: Materialized CTE Test
-- New Feature: Common Table Expressions can be materialized once and reused, instead of inlined every reference
-- Reference: https://github.com/ClickHouse/ClickHouse/pull/94849

-- Materialized CTE behavior is controlled by:
--   * Inline keyword:  WITH name AS MATERIALIZED (...)
--   * Setting:         enable_materialized_cte = 1

SET enable_materialized_cte = 1;

-- ============================================
-- 1. Basic Syntax
-- ============================================

SELECT '========== 1. Basic Materialized CTE ==========';

WITH expensive AS MATERIALIZED (
    SELECT number, number * 2 AS doubled
    FROM numbers(10)
)
SELECT *
FROM expensive
ORDER BY number;

-- ============================================
-- 2. CTE Referenced Multiple Times
-- ============================================

SELECT '========== 2. CTE Used in 3 Self-Joins ==========';

-- Without MATERIALIZED, the inner SELECT would be evaluated three separate times.
-- With MATERIALIZED, the expensive scan happens once and is reused.

WITH big AS MATERIALIZED (
    SELECT
        number AS id,
        cityHash64(toString(number)) AS h
    FROM numbers(100000)
)
SELECT
    count() AS total_rows,
    countDistinct(a.id) AS distinct_a,
    countDistinct(c.id) AS distinct_c
FROM big AS a
INNER JOIN big AS b ON a.id = b.id
INNER JOIN big AS c ON b.id = c.id;

-- ============================================
-- 3. EXPLAIN PIPELINE Confirms Single Scan
-- ============================================

SELECT '========== 3. EXPLAIN Difference (Inline vs Materialized) ==========';

-- Inline (default): subquery evaluated twice
EXPLAIN PIPELINE
WITH inline AS (SELECT number FROM numbers(1000))
SELECT count() FROM inline AS a JOIN inline AS b USING number
SETTINGS enable_materialized_cte = 0;

SELECT '--- vs Materialized ---';

-- Materialized: only one read of the source
EXPLAIN PIPELINE
WITH mat AS MATERIALIZED (SELECT number FROM numbers(1000))
SELECT count() FROM mat AS a JOIN mat AS b USING number
SETTINGS enable_materialized_cte = 1;

-- ============================================
-- 4. Real-World: Reused Aggregation
-- ============================================

SELECT '========== 4. Reused Aggregation (sales by category) ==========';

DROP TABLE IF EXISTS sales;
CREATE TABLE sales (
    order_id   UInt32,
    category   String,
    region     String,
    amount     Decimal(10, 2),
    order_date Date
) ENGINE = MergeTree() ORDER BY (order_date, order_id);

INSERT INTO sales VALUES
    (1, 'Electronics', 'NA', 1299.99, '2026-03-01'),
    (2, 'Electronics', 'EU',  899.50, '2026-03-01'),
    (3, 'Books',       'NA',   45.00, '2026-03-02'),
    (4, 'Electronics', 'NA',  599.00, '2026-03-02'),
    (5, 'Books',       'AS',   29.99, '2026-03-03'),
    (6, 'Home',        'NA',  150.00, '2026-03-03'),
    (7, 'Electronics', 'EU',  799.00, '2026-03-04'),
    (8, 'Books',       'NA',   60.00, '2026-03-04'),
    (9, 'Home',        'EU',  220.00, '2026-03-05'),
    (10,'Electronics', 'AS',  350.00, '2026-03-05');

-- The category_totals CTE is referenced twice — once for the rank and once for the share
WITH category_totals AS MATERIALIZED (
    SELECT category, sum(amount) AS total
    FROM sales
    GROUP BY category
)
SELECT
    ct.category,
    ct.total,
    round(ct.total / (SELECT sum(total) FROM category_totals), 4) AS share_of_grand_total
FROM category_totals AS ct
ORDER BY ct.total DESC;

-- ============================================
-- 5. Materialized CTE + Subquery Cache Benefit
-- ============================================

SELECT '========== 5. CTE With Window Function ==========';

WITH ranked AS MATERIALIZED (
    SELECT
        order_id,
        category,
        amount,
        rank() OVER (PARTITION BY category ORDER BY amount DESC) AS rk
    FROM sales
)
SELECT *
FROM ranked
WHERE rk = 1
ORDER BY category;

-- ============================================
-- 6. Toggle Setting Without Inline Keyword
-- ============================================

SELECT '========== 6. enable_materialized_cte Affects Bare WITH ==========';

-- With enable_materialized_cte = 1, a plain WITH ... AS ... CTE is also materialized
-- when referenced multiple times.
WITH plain AS (
    SELECT category, count() AS n
    FROM sales
    GROUP BY category
)
SELECT *
FROM plain
ORDER BY category
SETTINGS enable_materialized_cte = 1;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS sales;

SELECT '========== Test Complete ==========';
SELECT 'Materialized CTEs evaluate a subquery once and reuse the result across all references.' AS summary;
