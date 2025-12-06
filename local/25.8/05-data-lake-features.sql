-- ClickHouse 25.8 Feature: Data Lake Enhancements
-- Purpose: Test Iceberg/Delta Lake features including CREATE/DROP tables, writes, and time travel
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-08
-- Note: This demonstrates concepts. Full Iceberg/Delta Lake requires proper storage configuration.

-- ==========================================
-- Test 1: Data Lake Overview
-- ==========================================

SELECT '=== Test 1: ClickHouse 25.8 Data Lake Features ===' AS title;

SELECT '
📚 Data Lake Enhancements in ClickHouse 25.8:

1. Apache Iceberg Support:
   ✓ CREATE Iceberg tables directly
   ✓ DROP Iceberg tables
   ✓ Read and write Iceberg format
   ✓ Schema evolution support

2. Delta Lake Enhancements:
   ✓ Write to Delta Lake tables
   ✓ ACID transaction support
   ✓ Schema enforcement
   ✓ Data versioning

3. Time Travel:
   ✓ Query historical versions
   ✓ Version-based queries
   ✓ Timestamp-based queries
   ✓ Snapshot management

4. Unified Data Lake Access:
   - Single query engine for multiple formats
   - Parquet, Iceberg, Delta Lake support
   - S3, HDFS, GCS compatibility
   - Zero-copy data sharing
' AS overview;

-- ==========================================
-- Test 2: Create Sample Data Lake Tables
-- ==========================================

SELECT '=== Test 2: Create Product Catalog Data ===' AS title;

DROP TABLE IF EXISTS product_catalog_lake;

-- Create a regular table first (simulates data lake source)
CREATE TABLE product_catalog_lake
(
    product_id UInt32,
    product_name String,
    category String,
    subcategory String,
    brand String,
    price Decimal(10, 2),
    cost Decimal(10, 2),
    created_date Date,
    created_timestamp DateTime,
    is_active UInt8,
    attributes Map(String, String),
    tags Array(String)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_date)
ORDER BY product_id;

-- Insert sample product data
INSERT INTO product_catalog_lake
SELECT
    number + 1 AS product_id,
    concat('Product_', toString(number + 1)) AS product_name,
    ['Electronics', 'Clothing', 'Home', 'Sports', 'Books', 'Toys'][1 + (number % 6)] AS category,
    concat('SubCat_', toString(number % 20)) AS subcategory,
    concat('Brand_', toString(number % 50)) AS brand,
    round((number % 500) + 10.00, 2) AS price,
    round(((number % 500) + 10.00) * 0.6, 2) AS cost,
    today() - INTERVAL (number % 365) DAY AS created_date,
    now() - INTERVAL (number % 31536000) SECOND AS created_timestamp,
    if(number % 10 < 9, 1, 0) AS is_active,
    map('color', ['Red', 'Blue', 'Green', 'Black', 'White'][1 + (number % 5)],
        'size', ['S', 'M', 'L', 'XL'][1 + (number % 4)],
        'material', ['Cotton', 'Polyester', 'Leather', 'Metal'][1 + (number % 4)]) AS attributes,
    array('tag' || toString(number % 10), 'tag' || toString(number % 5)) AS tags
FROM numbers(10000);

SELECT format('✅ Created product catalog with {0} products', count()) AS status
FROM product_catalog_lake;

-- ==========================================
-- Test 3: Export to Parquet (Data Lake Format)
-- ==========================================

SELECT '=== Test 3: Export to Data Lake (Parquet Format) ===' AS title;

-- Export to Parquet format (common data lake format)
INSERT INTO FUNCTION file('/tmp/data_lake/products/v1/*.parquet', 'Parquet')
SELECT * FROM product_catalog_lake;

SELECT '✅ Data exported to data lake: /tmp/data_lake/products/v1/' AS status;

-- ==========================================
-- Test 4: Read from Data Lake
-- ==========================================

SELECT '=== Test 4: Query Data Lake (Version 1) ===' AS title;

-- Query the data lake
SELECT
    category,
    count() AS products,
    round(avg(price), 2) AS avg_price,
    round(sum(price), 2) AS total_value,
    countIf(is_active = 1) AS active_products
FROM file('/tmp/data_lake/products/v1/*.parquet', 'Parquet')
GROUP BY category
ORDER BY products DESC;

-- ==========================================
-- Test 5: Simulate Data Lake Updates (Versioning)
-- ==========================================

SELECT '=== Test 5: Create New Version with Updates ===' AS title;

-- Update some products (price increase)
CREATE OR REPLACE TABLE product_catalog_v2 AS
SELECT
    product_id,
    product_name,
    category,
    subcategory,
    brand,
    if(category = 'Electronics', round(price * 1.15, 2), price) AS price,  -- 15% increase for Electronics
    cost,
    created_date,
    created_timestamp,
    is_active,
    attributes,
    tags
FROM product_catalog_lake;

-- Export version 2
INSERT INTO FUNCTION file('/tmp/data_lake/products/v2/*.parquet', 'Parquet')
SELECT * FROM product_catalog_v2;

SELECT '✅ Version 2 created with price updates' AS status;

-- ==========================================
-- Test 6: Time Travel - Compare Versions
-- ==========================================

SELECT '=== Test 6: Time Travel - Version Comparison ===' AS title;

-- Version 1 (original)
WITH v1 AS (
    SELECT
        category,
        round(avg(price), 2) AS avg_price_v1
    FROM file('/tmp/data_lake/products/v1/*.parquet', 'Parquet')
    GROUP BY category
),
-- Version 2 (updated)
v2 AS (
    SELECT
        category,
        round(avg(price), 2) AS avg_price_v2
    FROM file('/tmp/data_lake/products/v2/*.parquet', 'Parquet')
    GROUP BY category
)
SELECT
    v1.category,
    v1.avg_price_v1 AS version_1_price,
    v2.avg_price_v2 AS version_2_price,
    round(v2.avg_price_v2 - v1.avg_price_v1, 2) AS price_change,
    round((v2.avg_price_v2 - v1.avg_price_v1) / v1.avg_price_v1 * 100, 2) AS price_change_pct
FROM v1
JOIN v2 ON v1.category = v2.category
ORDER BY price_change_pct DESC;

SELECT '✅ Time travel allows comparing historical versions' AS feature;

-- ==========================================
-- Test 7: Delta Lake Style Operations
-- ==========================================

SELECT '=== Test 7: Delta Lake Style - Incremental Updates ===' AS title;

-- Simulate incremental data
DROP TABLE IF EXISTS product_changes;

CREATE TABLE product_changes
(
    product_id UInt32,
    operation String,  -- 'INSERT', 'UPDATE', 'DELETE'
    change_timestamp DateTime,
    new_price Decimal(10, 2),
    change_reason String
)
ENGINE = MergeTree()
ORDER BY (change_timestamp, product_id);

-- Insert change log
INSERT INTO product_changes
SELECT
    (number % 1000) + 1 AS product_id,
    ['UPDATE', 'UPDATE', 'UPDATE', 'DELETE'][1 + (number % 4)] AS operation,
    now() - INTERVAL (number % 86400) SECOND AS change_timestamp,
    round((number % 300) + 50.00, 2) AS new_price,
    ['promotion', 'cost_change', 'market_adjustment', 'discontinuation'][1 + (number % 4)] AS change_reason
FROM numbers(100);

-- View change log
SELECT
    operation,
    count() AS changes,
    count(DISTINCT product_id) AS affected_products,
    arrayStringConcat(groupArray(DISTINCT change_reason), ', ') AS reasons
FROM product_changes
GROUP BY operation
ORDER BY changes DESC;

SELECT '✅ Change log tracks all modifications' AS delta_feature;

-- ==========================================
-- Test 8: Iceberg-Style Partitioning
-- ==========================================

SELECT '=== Test 8: Iceberg-Style Partition Evolution ===' AS title;

-- Export with date partitioning (Iceberg pattern)
INSERT INTO FUNCTION file('/tmp/data_lake/products_partitioned/year={year}/month={month}/*.parquet', 'Parquet')
SELECT
    *,
    toYear(created_date) AS year,
    toMonth(created_date) AS month
FROM product_catalog_lake;

SELECT '✅ Data partitioned by year/month (Iceberg style)' AS status;

-- Query specific partition
SELECT
    category,
    count() AS products,
    round(avg(price), 2) AS avg_price
FROM file('/tmp/data_lake/products_partitioned/year=*/month=*/*.parquet', 'Parquet')
WHERE year = toYear(today()) AND month = toMonth(today())
GROUP BY category
ORDER BY products DESC;

SELECT '✅ Partition pruning optimizes queries' AS optimization;

-- ==========================================
-- Test 9: Schema Evolution Simulation
-- ==========================================

SELECT '=== Test 9: Schema Evolution (Add Columns) ===' AS title;

-- Create table with additional columns (schema evolution)
CREATE OR REPLACE TABLE product_catalog_evolved AS
SELECT
    *,
    round(price * 1.2, 2) AS suggested_retail_price,
    ['online', 'retail', 'wholesale'][1 + (product_id % 3)] AS sales_channel,
    (product_id % 100) + 1 AS supplier_id
FROM product_catalog_lake;

-- Export evolved schema
INSERT INTO FUNCTION file('/tmp/data_lake/products/v3/*.parquet', 'Parquet')
SELECT * FROM product_catalog_evolved;

SELECT '✅ Schema evolved with new columns' AS status;
SELECT 'New columns: suggested_retail_price, sales_channel, supplier_id' AS new_fields;

-- Query evolved schema
SELECT
    sales_channel,
    count() AS products,
    round(avg(price), 2) AS avg_cost,
    round(avg(suggested_retail_price), 2) AS avg_retail,
    round(avg(suggested_retail_price - price), 2) AS avg_margin
FROM file('/tmp/data_lake/products/v3/*.parquet', 'Parquet')
GROUP BY sales_channel
ORDER BY products DESC;

-- ==========================================
-- Test 10: Multi-Version Query (Time Travel)
-- ==========================================

SELECT '=== Test 10: Query Across Multiple Versions ===' AS title;

-- Query all versions
WITH all_versions AS (
    SELECT *, 'v1' AS version FROM file('/tmp/data_lake/products/v1/*.parquet', 'Parquet')
    UNION ALL
    SELECT
        product_id, product_name, category, subcategory, brand,
        price, cost, created_date, created_timestamp, is_active,
        attributes, tags, 'v2' AS version
    FROM file('/tmp/data_lake/products/v2/*.parquet', 'Parquet')
)
SELECT
    version,
    count() AS products,
    round(avg(price), 2) AS avg_price,
    round(sum(price), 2) AS total_value,
    count(DISTINCT category) AS categories
FROM all_versions
GROUP BY version
ORDER BY version;

SELECT '✅ Time travel enables cross-version analysis' AS capability;

-- ==========================================
-- Test 11: Data Lake Metadata Query
-- ==========================================

SELECT '=== Test 11: Data Lake Metadata ===' AS title;

-- Analyze partitions (simulated metadata query)
WITH partition_info AS (
    SELECT
        toYear(created_date) AS year,
        toMonth(created_date) AS month,
        count() AS row_count,
        round(sum(price), 2) AS total_value,
        min(created_date) AS min_date,
        max(created_date) AS max_date
    FROM file('/tmp/data_lake/products_partitioned/year=*/month=*/*.parquet', 'Parquet')
    GROUP BY year, month
)
SELECT
    concat('year=', toString(year), '/month=', toString(month)) AS partition,
    row_count,
    total_value,
    min_date,
    max_date
FROM partition_info
ORDER BY year DESC, month DESC
LIMIT 12;

-- ==========================================
-- Test 12: Point-in-Time Query Simulation
-- ==========================================

SELECT '=== Test 12: Point-in-Time Query ===' AS title;

-- Query data as of specific time (using version)
SELECT
    'Point-in-Time: Version 1' AS query_time,
    count() AS total_products,
    round(avg(price), 2) AS avg_price,
    round(sum(price), 2) AS inventory_value,
    count(DISTINCT category) AS categories
FROM file('/tmp/data_lake/products/v1/*.parquet', 'Parquet')

UNION ALL

SELECT
    'Current: Version 3' AS query_time,
    count() AS total_products,
    round(avg(price), 2) AS avg_price,
    round(sum(price), 2) AS inventory_value,
    count(DISTINCT category) AS categories
FROM file('/tmp/data_lake/products/v3/*.parquet', 'Parquet');

-- ==========================================
-- Test 13: Audit Trail with Versions
-- ==========================================

SELECT '=== Test 13: Audit Trail for Data Changes ===' AS title;

-- Track changes across versions
WITH v1_products AS (
    SELECT product_id, price AS v1_price
    FROM file('/tmp/data_lake/products/v1/*.parquet', 'Parquet')
    WHERE category = 'Electronics'
),
v2_products AS (
    SELECT product_id, price AS v2_price
    FROM file('/tmp/data_lake/products/v2/*.parquet', 'Parquet')
    WHERE category = 'Electronics'
)
SELECT
    v1.product_id,
    v1.v1_price AS original_price,
    v2.v2_price AS updated_price,
    round(v2.v2_price - v1.v1_price, 2) AS price_increase,
    round((v2.v2_price - v1.v1_price) / v1.v1_price * 100, 2) AS increase_pct
FROM v1_products v1
JOIN v2_products v2 ON v1.product_id = v2.product_id
WHERE v1.v1_price != v2.v2_price
ORDER BY price_increase DESC
LIMIT 20;

SELECT '✅ Version tracking provides complete audit trail' AS audit_feature;

-- ==========================================
-- Performance Summary
-- ==========================================

SELECT '=== Data Lake Features Summary ===' AS title;

SELECT '
✅ Data Lake Enhancements in ClickHouse 25.8:

1. Apache Iceberg Support:
   ✓ CREATE/DROP Iceberg tables
   ✓ Native Iceberg format support
   ✓ Metadata management
   ✓ Schema evolution
   ✓ Partition evolution
   ✓ ACID transactions

2. Delta Lake Enhancements:
   ✓ Write to Delta Lake tables
   ✓ ACID transaction support
   ✓ Schema enforcement
   ✓ Data versioning
   ✓ Time travel queries
   ✓ Merge operations

3. Time Travel Capabilities:
   ✓ Query historical versions
   ✓ Point-in-time queries
   ✓ Version comparison
   ✓ Audit trail support
   ✓ Rollback capabilities
   ✓ Data recovery

4. Unified Data Access:
   - Single engine for multiple formats
   - Parquet, Iceberg, Delta Lake
   - S3, HDFS, GCS, Azure support
   - Zero-copy data sharing
   - Cross-format queries

5. Key Benefits:
   📊 Interoperability with Spark, Presto, Trino
   📊 ACID guarantees for data lake
   📊 Schema evolution without rewrites
   📊 Time travel for compliance
   📊 Efficient metadata operations
   📊 Multi-engine ecosystem

6. Use Cases:
   ✓ Data Lake Analytics
      - Query S3/HDFS directly
      - Multi-format support
      - Partition pruning

   ✓ Data Engineering:
      - ETL pipelines
      - Data quality checks
      - Schema evolution

   ✓ Data Science:
      - Feature engineering
      - Historical analysis
      - Experiment tracking

   ✓ Compliance & Audit:
      - Time travel for compliance
      - Audit trail
      - Data lineage

   ✓ Real-time Analytics:
      - Streaming + batch
      - Incremental updates
      - ACID guarantees

7. Iceberg Table Operations:
   -- Create Iceberg table
   CREATE TABLE iceberg_table
   ENGINE = Iceberg(''s3://bucket/path'')
   ...

   -- Drop Iceberg table
   DROP TABLE iceberg_table;

   -- Query with time travel
   SELECT * FROM iceberg_table
   FOR SYSTEM_TIME AS OF ''2024-12-01'';

8. Delta Lake Operations:
   -- Write to Delta Lake
   INSERT INTO delta_table ...

   -- Query specific version
   SELECT * FROM delta_table
   VERSION AS OF 42;

   -- Query as of timestamp
   SELECT * FROM delta_table
   TIMESTAMP AS OF ''2024-12-01 00:00:00'';

💡 Best Practices:
- Use partitioning for large datasets
- Leverage time travel for debugging
- Implement schema evolution carefully
- Monitor metadata operations
- Optimize partition strategy
- Use compression for storage efficiency

🚀 Performance Tips:
- Partition by date for time-series data
- Use column pruning in queries
- Leverage metadata for statistics
- Cache frequently accessed versions
- Use predicate pushdown
- Optimize file sizes (128MB-1GB)

🎯 Integration Examples:
- ClickHouse + Spark: Shared Iceberg tables
- ClickHouse + Presto: Federated queries
- ClickHouse + Airflow: ETL orchestration
- ClickHouse + dbt: Data transformations
- ClickHouse + Kafka: Streaming ingestion
' AS summary;

-- Optional: Cleanup (commented out by default)
-- DROP TABLE IF EXISTS product_catalog_lake;
-- DROP TABLE IF EXISTS product_catalog_v2;
-- DROP TABLE IF EXISTS product_catalog_evolved;
-- DROP TABLE IF EXISTS product_changes;
-- SELECT '🧹 Cleanup completed' AS status;
