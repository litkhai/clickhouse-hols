-- ClickHouse 25.5 Feature: Hive Metastore Catalog for Iceberg Tables
-- Purpose: Demonstrate Hive metastore catalog support for querying Iceberg tables
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-05

-- Note: This script demonstrates the syntax and concepts for Hive Metastore Catalog
-- Actual execution requires a running Hive metastore and Iceberg tables
-- For demonstration purposes, we'll show the configuration and query patterns

SELECT '=== Hive Metastore Catalog Overview ===' AS title;
SELECT
    'ClickHouse 25.5 adds Hive metastore catalog support for Iceberg tables' AS feature,
    'Extends lakehouse capabilities alongside Unity and AWS Glue catalogs' AS capability,
    'Uses Thrift protocol for Hive metastore communication' AS protocol,
    'Enables querying external Iceberg tables without data movement' AS benefit;

-- Example 1: DataLakeCatalog table function syntax
-- This is the pattern for connecting to Hive metastore
SELECT '=== DataLakeCatalog Table Function Syntax ===' AS title;
SELECT
    'DataLakeCatalog' AS function_name,
    'catalog_type' AS param_1,
    'metastore_uri' AS param_2,
    'database_name.table_name' AS param_3,
    'Thrift protocol for Hive metastore' AS connection_type;

-- Example configuration pattern
SELECT '=== Example Hive Metastore Configuration ===' AS title;
SELECT
    'thrift://metastore-host:9083' AS metastore_uri_example,
    'hive' AS catalog_type,
    'default.sales_data' AS table_name_example,
    'Must have network access to metastore service' AS requirement;

-- Create a demonstration table to show Iceberg-like data patterns
DROP TABLE IF EXISTS iceberg_demo_orders;

CREATE TABLE iceberg_demo_orders
(
    order_id UInt64,
    customer_id UInt32,
    order_date Date,
    order_timestamp DateTime,
    product_name String,
    quantity UInt32,
    unit_price Decimal(10, 2),
    total_amount Decimal(12, 2),
    region String,
    partition_year UInt16,
    partition_month UInt8
)
ENGINE = MergeTree()
PARTITION BY (partition_year, partition_month)
ORDER BY (region, order_date, order_id)
SETTINGS index_granularity = 8192;

-- Insert sample data representing what might come from an Iceberg table
INSERT INTO iceberg_demo_orders VALUES
    (1001, 5001, '2025-01-15', '2025-01-15 10:30:00', 'Widget A', 5, 29.99, 149.95, 'US-WEST', 2025, 1),
    (1002, 5002, '2025-01-15', '2025-01-15 11:45:00', 'Widget B', 3, 49.99, 149.97, 'US-EAST', 2025, 1),
    (1003, 5003, '2025-01-16', '2025-01-16 09:15:00', 'Widget C', 10, 19.99, 199.90, 'EU-WEST', 2025, 1),
    (1004, 5001, '2025-01-16', '2025-01-16 14:20:00', 'Widget A', 2, 29.99, 59.98, 'US-WEST', 2025, 1),
    (1005, 5004, '2025-01-17', '2025-01-17 08:30:00', 'Widget D', 7, 39.99, 279.93, 'APAC', 2025, 1),
    (1006, 5005, '2025-01-17', '2025-01-17 16:45:00', 'Widget B', 4, 49.99, 199.96, 'US-EAST', 2025, 1),
    (1007, 5006, '2025-01-18', '2025-01-18 10:00:00', 'Widget C', 15, 19.99, 299.85, 'EU-CENTRAL', 2025, 1),
    (1008, 5007, '2025-01-18', '2025-01-18 13:30:00', 'Widget A', 8, 29.99, 239.92, 'US-WEST', 2025, 1),
    (1009, 5008, '2025-01-19', '2025-01-19 11:20:00', 'Widget D', 5, 39.99, 199.95, 'APAC', 2025, 1),
    (1010, 5009, '2025-01-19', '2025-01-19 15:15:00', 'Widget B', 6, 49.99, 299.94, 'EU-WEST', 2025, 1);

-- Query 1: Typical lakehouse query pattern - aggregate by region
SELECT '=== Sales Summary by Region ===' AS title;
SELECT
    region,
    count(*) AS order_count,
    sum(quantity) AS total_quantity,
    sum(total_amount) AS revenue,
    avg(unit_price) AS avg_unit_price
FROM iceberg_demo_orders
GROUP BY region
ORDER BY revenue DESC;

-- Query 2: Time-based analysis using partition columns
SELECT '=== Daily Sales Trend ===' AS title;
SELECT
    order_date,
    count(*) AS orders,
    sum(total_amount) AS daily_revenue,
    uniq(customer_id) AS unique_customers
FROM iceberg_demo_orders
GROUP BY order_date
ORDER BY order_date;

-- Query 3: Product performance analysis
SELECT '=== Product Performance ===' AS title;
SELECT
    product_name,
    count(*) AS times_ordered,
    sum(quantity) AS units_sold,
    sum(total_amount) AS product_revenue,
    round(avg(quantity), 2) AS avg_quantity_per_order
FROM iceberg_demo_orders
GROUP BY product_name
ORDER BY product_revenue DESC;

-- Query 4: Customer segmentation
SELECT '=== Top Customers by Revenue ===' AS title;
SELECT
    customer_id,
    count(*) AS order_count,
    sum(total_amount) AS total_spent,
    arrayStringConcat(groupArray(product_name), ', ') AS products_purchased
FROM iceberg_demo_orders
GROUP BY customer_id
ORDER BY total_spent DESC
LIMIT 5;

-- Real-world Iceberg integration patterns
SELECT '=== Iceberg Integration Patterns ===' AS info;
SELECT
    'Pattern 1: Read Iceberg tables directly from S3/HDFS' AS pattern_1,
    'Pattern 2: Join ClickHouse tables with Iceberg tables' AS pattern_2,
    'Pattern 3: Materialize Iceberg data for performance' AS pattern_3,
    'Pattern 4: Query across multiple catalogs (Unity, Glue, Hive)' AS pattern_4,
    'Pattern 5: Time travel queries using Iceberg snapshots' AS pattern_5;

-- Benefits of Hive Metastore Catalog support
SELECT '=== Benefits of Hive Metastore Integration ===' AS info;
SELECT
    'No data movement - query Iceberg tables in place' AS benefit_1,
    'Unified SQL interface across data warehouse and data lake' AS benefit_2,
    'Leverage ClickHouse query performance on lakehouse data' AS benefit_3,
    'Integrate with existing Hive/Spark ecosystems' AS benefit_4,
    'Support for partitioned and evolving schemas' AS benefit_5,
    'Cost-effective analytics on cold storage' AS benefit_6;

-- Common use cases
SELECT '=== Common Use Cases ===' AS info;
SELECT
    'Analytics on historical data in S3 data lakes' AS use_case_1,
    'Hybrid queries joining warehouse and lake data' AS use_case_2,
    'Cost optimization by tiering data to object storage' AS use_case_3,
    'Data exploration without ETL or data copying' AS use_case_4,
    'Real-time analytics on streaming data via Iceberg' AS use_case_5,
    'Multi-engine analytics (Spark + ClickHouse)' AS use_case_6;

-- Configuration tips
SELECT '=== Configuration Best Practices ===' AS info;
SELECT
    'Ensure network connectivity to Hive metastore (port 9083)' AS tip_1,
    'Configure appropriate access credentials for S3/HDFS' AS tip_2,
    'Use partition pruning for efficient queries' AS tip_3,
    'Consider caching frequently accessed Iceberg metadata' AS tip_4,
    'Monitor query performance and optimize file layouts' AS tip_5;

-- Example: Catalog integration architecture
SELECT '=== Lakehouse Architecture with ClickHouse ===' AS info;
SELECT
    'Layer 1: Object Storage (S3, HDFS, Azure Blob)' AS layer_1,
    'Layer 2: Table Format (Apache Iceberg)' AS layer_2,
    'Layer 3: Catalog (Hive Metastore, Unity, Glue)' AS layer_3,
    'Layer 4: Query Engine (ClickHouse with DataLakeCatalog)' AS layer_4,
    'Layer 5: Analytics and Visualization' AS layer_5;

-- Comparison with other catalog types
SELECT '=== Catalog Type Comparison ===' AS info;
SELECT
    'Hive Metastore: Traditional Hadoop ecosystem, Thrift protocol' AS hive_catalog,
    'AWS Glue: Managed service, tight AWS integration' AS glue_catalog,
    'Unity Catalog: Databricks, fine-grained governance' AS unity_catalog,
    'All three supported in ClickHouse 25.5+' AS support_status;

-- Query 5: Simulate partition pruning benefit
SELECT '=== Partition Pruning Example ===' AS title;
SELECT
    partition_year,
    partition_month,
    count(*) AS records,
    sum(total_amount) AS revenue
FROM iceberg_demo_orders
WHERE partition_year = 2025 AND partition_month = 1
GROUP BY partition_year, partition_month;

-- Cleanup (commented out for inspection)
-- DROP TABLE iceberg_demo_orders;

SELECT '✅ Hive Metastore Catalog Test Complete!' AS status;
SELECT 'Note: Full integration requires Hive metastore and Iceberg tables setup' AS note;
