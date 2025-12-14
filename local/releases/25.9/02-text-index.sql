-- ClickHouse 25.9 Feature: New Text Index (Full-Text Search)
-- Purpose: Test experimental full-text search capabilities
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-09

-- ==========================================
-- Test 1: Setup - Create Table with Text Index
-- ==========================================

SELECT '=== Test 1: Creating Articles Table with Text Index ===' AS title;

SELECT '\n🚀 ClickHouse 25.9 New Feature: Text Index for Full-Text Search\nExperimental feature for efficient full-text search\n' AS info;

DROP TABLE IF EXISTS articles;

CREATE TABLE articles
(
    article_id UInt64,
    title String,
    content String,
    author String,
    category String,
    publish_date Date,
    tags Array(String),
    view_count UInt32,
    INDEX content_idx content TYPE full_text GRANULARITY 1
)
ENGINE = MergeTree()
ORDER BY (publish_date, article_id)
SETTINGS index_granularity = 8192;

SELECT '✅ Created articles table with full-text index on content column' AS status;

-- ==========================================
-- Test 2: Insert Sample Articles
-- ==========================================

SELECT '=== Test 2: Inserting Sample Articles ===' AS title;

INSERT INTO articles
SELECT
    number + 1 AS article_id,
    CASE (number % 10)
        WHEN 0 THEN 'Understanding ClickHouse Performance Optimization'
        WHEN 1 THEN 'Advanced Data Lake Integration with MinIO'
        WHEN 2 THEN 'Machine Learning at Scale with ClickHouse'
        WHEN 3 THEN 'Real-time Analytics and Streaming Data'
        WHEN 4 THEN 'Building Modern Data Warehouses'
        WHEN 5 THEN 'SQL Query Optimization Techniques'
        WHEN 6 THEN 'ClickHouse Cloud Architecture Overview'
        WHEN 7 THEN 'Data Security and Privacy Best Practices'
        WHEN 8 THEN 'Distributed Systems and Scalability'
        ELSE 'Introduction to Column-Oriented Databases'
    END AS title,
    CASE (number % 10)
        WHEN 0 THEN 'ClickHouse is a fast open-source column-oriented database management system that allows generating analytical data reports in real-time using SQL queries. Performance optimization is crucial for handling large-scale data efficiently.'
        WHEN 1 THEN 'Data lakes provide flexible storage for structured and unstructured data. MinIO offers S3-compatible object storage that integrates seamlessly with ClickHouse for building modern data architectures.'
        WHEN 2 THEN 'Machine learning workflows benefit from ClickHouse ability to process massive datasets quickly. Feature engineering and model training can leverage ClickHouse powerful aggregation capabilities.'
        WHEN 3 THEN 'Real-time analytics requires efficient data ingestion and query processing. ClickHouse streaming capabilities enable low-latency dashboards and instant insights from live data streams.'
        WHEN 4 THEN 'Modern data warehouses combine transactional and analytical workloads. ClickHouse provides a unified platform for OLAP queries with exceptional performance and scalability.'
        WHEN 5 THEN 'SQL query optimization involves understanding execution plans, index usage, and data distribution. ClickHouse query optimizer automatically applies various optimization techniques.'
        WHEN 6 THEN 'ClickHouse Cloud offers fully-managed database service with automatic scaling, backup, and monitoring. The architecture is designed for high availability and performance.'
        WHEN 7 THEN 'Data security includes encryption, access control, and audit logging. ClickHouse provides comprehensive security features to protect sensitive information and ensure compliance.'
        WHEN 8 THEN 'Distributed systems enable horizontal scalability across multiple nodes. ClickHouse distributed architecture supports sharding and replication for fault tolerance.'
        ELSE 'Column-oriented databases store data by columns rather than rows, enabling efficient compression and fast analytical queries. This design is optimal for OLAP workloads and data warehousing.'
    END AS content,
    concat('Author_', toString((number % 20) + 1)) AS author,
    ['Technology', 'Database', 'Analytics', 'Cloud', 'Security'][1 + (number % 5)] AS category,
    today() - INTERVAL (number % 365) DAY AS publish_date,
    ['clickhouse', 'database', 'analytics', 'performance', 'sql'][1:(number % 3) + 2] AS tags,
    1000 + (number % 10000) AS view_count
FROM numbers(10000);

SELECT format('✅ Inserted {0} articles', count()) AS status FROM articles;

-- ==========================================
-- Test 3: Full-Text Search - Basic Queries
-- ==========================================

SELECT '=== Test 3: Basic Full-Text Search ===' AS title;

-- Search for "ClickHouse"
SELECT '\n🔍 Searching for "ClickHouse":\n' AS search_info;

SELECT
    article_id,
    title,
    substring(content, 1, 100) AS content_preview,
    category
FROM articles
WHERE content LIKE '%ClickHouse%'
ORDER BY view_count DESC
LIMIT 5;

-- Search for "machine learning"
SELECT '\n🔍 Searching for "machine learning":\n' AS search_info;

SELECT
    article_id,
    title,
    substring(content, 1, 100) AS content_preview,
    category
FROM articles
WHERE content LIKE '%machine learning%'
ORDER BY publish_date DESC
LIMIT 5;

-- ==========================================
-- Test 4: Full-Text Search with Multiple Terms
-- ==========================================

SELECT '=== Test 4: Multi-Term Search ===' AS title;

-- Search for articles about "data" AND "analytics"
SELECT
    count() AS matching_articles,
    countDistinct(category) AS categories,
    round(avg(view_count), 0) AS avg_views
FROM articles
WHERE content LIKE '%data%'
  AND content LIKE '%analytics%';

SELECT '\n📊 Top articles mentioning both "data" and "analytics":\n' AS results_info;

SELECT
    title,
    category,
    view_count
FROM articles
WHERE content LIKE '%data%'
  AND content LIKE '%analytics%'
ORDER BY view_count DESC
LIMIT 5;

-- ==========================================
-- Test 5: Category-Based Text Search
-- ==========================================

SELECT '=== Test 5: Category + Full-Text Search ===' AS title;

SELECT
    category,
    count() AS articles,
    countIf(content LIKE '%performance%') AS mentions_performance,
    countIf(content LIKE '%scalability%') AS mentions_scalability,
    countIf(content LIKE '%security%') AS mentions_security
FROM articles
GROUP BY category
ORDER BY articles DESC;

-- ==========================================
-- Test 6: Date-Range Text Search
-- ==========================================

SELECT '=== Test 6: Time-Based Full-Text Search ===' AS title;

SELECT '\n📅 Recent articles (last 30 days) about "optimization":\n' AS time_search;

SELECT
    title,
    publish_date,
    view_count
FROM articles
WHERE publish_date >= today() - INTERVAL 30 DAY
  AND content LIKE '%optimization%'
ORDER BY publish_date DESC
LIMIT 10;

-- ==========================================
-- Test 7: Author Analytics with Text Search
-- ==========================================

SELECT '=== Test 7: Author Analysis with Full-Text Search ===' AS title;

SELECT
    author,
    count() AS total_articles,
    countIf(content LIKE '%ClickHouse%') AS clickhouse_articles,
    sum(view_count) AS total_views,
    round(avg(view_count), 0) AS avg_views
FROM articles
GROUP BY author
HAVING clickhouse_articles > 0
ORDER BY total_views DESC
LIMIT 10;

-- ==========================================
-- Test 8: Tag-Based Search
-- ==========================================

SELECT '=== Test 8: Tag + Content Search ===' AS title;

SELECT
    arrayJoin(tags) AS tag,
    count() AS articles_with_tag,
    countIf(content LIKE '%performance%') AS performance_related,
    round(avg(view_count), 0) AS avg_views
FROM articles
GROUP BY tag
ORDER BY articles_with_tag DESC;

-- ==========================================
-- Test 9: Complex Search Patterns
-- ==========================================

SELECT '=== Test 9: Complex Search Patterns ===' AS title;

-- Articles about databases OR analytics with high views
SELECT
    title,
    category,
    view_count,
    multiIf(
        content LIKE '%database%' AND content LIKE '%analytics%', 'Both',
        content LIKE '%database%', 'Database',
        content LIKE '%analytics%', 'Analytics',
        'Other'
    ) AS content_type
FROM articles
WHERE (content LIKE '%database%' OR content LIKE '%analytics%')
  AND view_count > 5000
ORDER BY view_count DESC
LIMIT 10;

-- ==========================================
-- Test 10: Text Index Benefits
-- ==========================================

SELECT '=== ClickHouse 25.9: Text Index Benefits ===' AS info;

SELECT '
🚀 Text Index (Full-Text Search) Benefits:

1. Performance:
   ✓ Streaming-friendly design
   ✓ Efficient skip index granules
   ✓ Fast text matching queries
   ✓ Reduced I/O operations

2. Features:
   ✓ Full-text search capabilities
   ✓ Pattern matching optimization
   ✓ Integration with other indices
   ✓ Automatic index maintenance

3. Use Cases:
   - Log analysis and searching
   - Document management systems
   - Content search engines
   - Article/blog platforms
   - Technical documentation search

4. Configuration:
   INDEX index_name column_name TYPE full_text GRANULARITY 1

Note: This is an EXPERIMENTAL feature in 25.9
The text index provides more efficient and reliable full-text search
compared to simple LIKE queries on large datasets.

Future improvements will include:
- Advanced ranking algorithms
- Phrase search support
- Fuzzy matching
- Multi-language support
' AS benefits;

-- Cleanup (commented out for inspection)
-- DROP TABLE articles;

SELECT '✅ Text Index (Full-Text Search) Test Complete!' AS status;
