-- ClickHouse 26.4: NATURAL JOIN + VALUES Table Expression Test
-- New Features:
--   * NATURAL JOIN — auto-matches on all same-named columns, deduplicates them in the result
--   * VALUES (...) AS t(col, ...) — SQL-standard VALUES clause usable in FROM
-- References:
--   https://github.com/ClickHouse/ClickHouse/pull/99840
--   https://github.com/ClickHouse/ClickHouse/pull/100143

-- ============================================
-- 1. VALUES Clause as a Table Expression
-- ============================================

SELECT '========== 1. VALUES in FROM Clause ==========';

-- Inline literal table, no CREATE TABLE needed
SELECT *
FROM (VALUES (1, 'red'), (2, 'green'), (3, 'blue')) AS t(id, color)
ORDER BY id;

-- VALUES with multiple columns and types
SELECT *
FROM (VALUES
    (1, 'Alice',   29.99, '2026-01-15'),
    (2, 'Bob',     49.50, '2026-02-20'),
    (3, 'Carol',  120.00, '2026-03-10')
) AS orders(order_id, customer, amount, order_date);

-- VALUES inside a CTE
WITH currencies AS (
    SELECT * FROM (VALUES ('USD', 1.0), ('EUR', 1.08), ('JPY', 0.0066), ('KRW', 0.00072)) AS c(code, rate_usd)
)
SELECT * FROM currencies ORDER BY rate_usd DESC;

-- ============================================
-- 2. NATURAL JOIN — Auto-Match by Column Name
-- ============================================

SELECT '========== 2. NATURAL JOIN Basics ==========';

DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS departments;

CREATE TABLE employees (
    emp_id     UInt32,
    name       String,
    dept_id    UInt32,
    salary     Decimal(10,2)
) ENGINE = MergeTree() ORDER BY emp_id;

CREATE TABLE departments (
    dept_id    UInt32,
    dept_name  String,
    budget     Decimal(12,2)
) ENGINE = MergeTree() ORDER BY dept_id;

INSERT INTO employees VALUES
    (1, 'Alice',   10, 95000),
    (2, 'Bob',     20, 80000),
    (3, 'Carol',   10, 105000),
    (4, 'Dave',    30, 70000),
    (5, 'Eve',     20, 90000);

INSERT INTO departments VALUES
    (10, 'Engineering', 1000000),
    (20, 'Sales',        500000),
    (30, 'Marketing',    300000);

-- NATURAL JOIN auto-detects 'dept_id' as the join key
-- and returns it ONCE (not duplicated)
SELECT *
FROM employees NATURAL JOIN departments
ORDER BY emp_id;

-- ============================================
-- 3. Compare NATURAL JOIN vs Explicit JOIN
-- ============================================

SELECT '========== 3. Column-by-Column Comparison ==========';

-- Explicit JOIN: dept_id appears twice (qualified)
SELECT 'Explicit JOIN' AS join_type, count() AS col_count
FROM (
    SELECT *
    FROM employees AS e
    INNER JOIN departments AS d ON e.dept_id = d.dept_id
    LIMIT 1
);

-- NATURAL JOIN: dept_id appears once
SELECT 'NATURAL JOIN' AS join_type, count() AS col_count
FROM (
    SELECT *
    FROM employees NATURAL JOIN departments
    LIMIT 1
);

-- ============================================
-- 4. NATURAL JOIN with VALUES
-- ============================================

SELECT '========== 4. NATURAL JOIN with Inline VALUES ==========';

SELECT *
FROM
    (VALUES (1, 'A'), (2, 'B'), (3, 'C')) AS x(id, letter)
NATURAL JOIN
    (VALUES (1, 100), (2, 200), (3, 300)) AS y(id, score)
ORDER BY id;

-- ============================================
-- 5. Real-World: Reference Data Lookups
-- ============================================

SELECT '========== 5. Country Code Lookup with VALUES ==========';

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id      UInt32,
    country_code  String,
    amount        Decimal(10, 2)
) ENGINE = MergeTree() ORDER BY order_id;

INSERT INTO orders VALUES
    (1, 'US', 100.00),
    (2, 'KR', 150.00),
    (3, 'JP',  75.00),
    (4, 'DE',  60.00),
    (5, 'US', 200.00),
    (6, 'KR',  90.00);

-- Use VALUES as an inline lookup table instead of creating a temp table
WITH country_names AS (
    SELECT *
    FROM (VALUES
        ('US', 'United States'),
        ('KR', 'South Korea'),
        ('JP', 'Japan'),
        ('DE', 'Germany')
    ) AS c(country_code, country_name)
)
SELECT
    o.order_id,
    cn.country_name,
    o.amount
FROM orders AS o
NATURAL JOIN country_names AS cn
ORDER BY o.order_id;

-- ============================================
-- 6. Multi-Column NATURAL JOIN
-- ============================================

SELECT '========== 6. NATURAL JOIN with Multiple Shared Columns ==========';

DROP TABLE IF EXISTS prod_a;
DROP TABLE IF EXISTS prod_b;

CREATE TABLE prod_a (region String, category String, units UInt32) ENGINE = Memory;
CREATE TABLE prod_b (region String, category String, revenue Decimal(10,2)) ENGINE = Memory;

INSERT INTO prod_a VALUES ('NA', 'Electronics', 100), ('NA', 'Books', 50), ('EU', 'Electronics', 80);
INSERT INTO prod_b VALUES ('NA', 'Electronics', 50000), ('NA', 'Books', 1500), ('EU', 'Electronics', 36000);

-- region AND category are auto-detected as the join keys
SELECT *
FROM prod_a NATURAL JOIN prod_b
ORDER BY region, category;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS employees;
-- DROP TABLE IF EXISTS departments;
-- DROP TABLE IF EXISTS orders;
-- DROP TABLE IF EXISTS prod_a;
-- DROP TABLE IF EXISTS prod_b;

SELECT '========== Test Complete ==========';
SELECT 'NATURAL JOIN + VALUES eliminate boilerplate for joins and inline tables.' AS summary;
