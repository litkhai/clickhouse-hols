-- ClickHouse 25.10 Feature: Negative LIMIT and OFFSET
-- Purpose: Test negative LIMIT and OFFSET support
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-10

-- Create sample table
DROP TABLE IF EXISTS negative_limit_demo;

CREATE TABLE negative_limit_demo
(
    id UInt32,
    name String,
    score Int32,
    category String
)
ENGINE = MergeTree()
ORDER BY id;

-- Insert sample data
INSERT INTO negative_limit_demo VALUES
    (1, 'Alice', 95, 'A'),
    (2, 'Bob', 87, 'B'),
    (3, 'Charlie', 92, 'A'),
    (4, 'David', 78, 'C'),
    (5, 'Eve', 88, 'B'),
    (6, 'Frank', 91, 'A'),
    (7, 'Grace', 85, 'B'),
    (8, 'Henry', 94, 'A'),
    (9, 'Iris', 82, 'C'),
    (10, 'Jack', 90, 'A');

-- Query 1: View all data
SELECT '=== All Records ===' AS title;
SELECT * FROM negative_limit_demo ORDER BY id;

-- Query 2: Traditional LIMIT - get first 3 records
SELECT '=== Traditional LIMIT 3 ===' AS title;
SELECT * FROM negative_limit_demo ORDER BY id LIMIT 3;

-- Query 3: Negative LIMIT - get last 3 records (new in 25.10!)
SELECT '=== Negative LIMIT -3 (Last 3 records) ===' AS title;
SELECT * FROM negative_limit_demo ORDER BY id LIMIT -3;

-- Query 4: Traditional OFFSET - skip first 2 records
SELECT '=== Traditional OFFSET 2 LIMIT 3 ===' AS title;
SELECT * FROM negative_limit_demo ORDER BY id LIMIT 3 OFFSET 2;

-- Query 5: Negative OFFSET - skip last 2 records (new in 25.10!)
SELECT '=== Negative OFFSET -2 (Skip last 2) ===' AS title;
SELECT * FROM negative_limit_demo ORDER BY id OFFSET -2;

-- Query 6: Combination - Negative OFFSET (Skip last 2)
SELECT '=== OFFSET -2 LIMIT 5 (Last 5, skip last 2) ===' AS title;
SELECT * FROM negative_limit_demo ORDER BY id LIMIT 5 OFFSET -2;

-- Query 7: Get top scorers, then last 2 of them
SELECT '=== Top Scorers, Last 2 ===' AS title;
SELECT * FROM negative_limit_demo ORDER BY score DESC LIMIT -2;

-- Query 8: Practical use case - pagination from the end
SELECT '=== Pagination from End ===' AS title;
SELECT
    'Page from end (last 5 records)' AS description,
    id,
    name,
    score
FROM negative_limit_demo
ORDER BY id
LIMIT -5;

-- Query 9: Category analysis with negative limit
SELECT '=== Last 3 in Each Category ===' AS title;
SELECT
    category,
    name,
    score
FROM
(
    SELECT
        *,
        row_number() OVER (PARTITION BY category ORDER BY id) as rn,
        count() OVER (PARTITION BY category) as total
    FROM negative_limit_demo
)
WHERE rn > total - 3
ORDER BY category, id;

-- Query 10: Compare positive vs negative LIMIT
SELECT '=== Comparison: First 3 vs Last 3 ===' AS title;
SELECT * FROM (
    SELECT 'First 3' AS type, id, name, score
    FROM negative_limit_demo
    ORDER BY score DESC
    LIMIT 3
    UNION ALL
    SELECT 'Last 3' AS type, id, name, score
    FROM negative_limit_demo
    ORDER BY score DESC
    LIMIT -3
)
ORDER BY type, score DESC;

-- Practical Benefits
SELECT '=== Benefits of Negative LIMIT/OFFSET ===' AS info;
SELECT
    'Simpler syntax for getting last N records' AS benefit_1,
    'No need for subqueries or window functions for tail queries' AS benefit_2,
    'More intuitive reverse pagination' AS benefit_3,
    'Better performance for "tail" queries' AS benefit_4;

-- Cleanup
-- DROP TABLE negative_limit_demo;

SELECT '✅ Negative LIMIT/OFFSET Test Complete!' AS status;
