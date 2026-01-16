-- ClickHouse 25.5 Feature: New Functions
-- Purpose: Test new functions introduced in ClickHouse 25.5
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-05

SELECT '=== New Functions in ClickHouse 25.5 ===' AS title;
SELECT
    'sparseGrams - finds all substrings of length >= n' AS function_1,
    'mapContainsKey - checks if map contains a key' AS function_2,
    'mapContainsValue - checks if map contains a value' AS function_3,
    'mapContainsValueLike - checks if map contains value matching pattern' AS function_4,
    'icebergHash - Iceberg table hashing function' AS function_5,
    'icebergBucketTransform - Iceberg bucketing transformation' AS function_6;

-- =====================================
-- 1. sparseGrams Function
-- =====================================

SELECT '=== sparseGrams() Function ===' AS title;
SELECT
    'Extracts all substrings with length >= n from a string' AS description,
    'Useful for text analysis, fuzzy matching, and search' AS use_case;

-- Example 1: Basic sparseGrams usage
SELECT '--- Basic sparseGrams Examples ---' AS example;
SELECT
    'ClickHouse' AS text,
    sparseGrams('ClickHouse', 3) AS grams_3,
    sparseGrams('ClickHouse', 4) AS grams_4,
    sparseGrams('ClickHouse', 5) AS grams_5;

-- Example 2: Text analysis with sparseGrams
DROP TABLE IF EXISTS text_documents;

CREATE TABLE text_documents
(
    doc_id UInt32,
    title String,
    content String,
    category String
)
ENGINE = MergeTree()
ORDER BY doc_id;

INSERT INTO text_documents VALUES
    (1, 'Database Performance', 'ClickHouse delivers high performance analytics', 'Technology'),
    (2, 'Data Analytics Guide', 'Modern analytics requires fast query engines', 'Technology'),
    (3, 'Cloud Computing', 'Cloud platforms enable scalable applications', 'Technology'),
    (4, 'Machine Learning Basics', 'Machine learning models need quality data', 'AI'),
    (5, 'Big Data Processing', 'Processing large datasets efficiently matters', 'Technology');

-- Query: Find similar documents using sparseGrams
SELECT '--- Document Similarity Using sparseGrams ---' AS query;
SELECT
    doc_id,
    title,
    length(sparseGrams(content, 4)) AS unique_4grams,
    length(sparseGrams(content, 5)) AS unique_5grams
FROM text_documents
ORDER BY unique_4grams DESC;

-- =====================================
-- 2. Map Functions: mapContainsKey, mapContainsValue, mapContainsValueLike
-- =====================================

SELECT '=== Map Functions ===' AS title;
SELECT
    'mapContainsKey - checks if map has a specific key' AS func_1,
    'mapContainsValue - checks if map has a specific value' AS func_2,
    'mapContainsValueLike - checks if map has value matching pattern' AS func_3;

-- Create a table with map columns
DROP TABLE IF EXISTS user_preferences;

CREATE TABLE user_preferences
(
    user_id UInt32,
    user_name String,
    settings Map(String, String),
    features Map(String, String),
    metadata Map(String, String)
)
ENGINE = MergeTree()
ORDER BY user_id;

INSERT INTO user_preferences VALUES
    (1, 'Alice', map('theme', 'dark', 'language', 'en', 'timezone', 'UTC'),
     map('notifications', 'enabled', 'beta', 'true'),
     map('plan', 'premium', 'region', 'us-west')),
    (2, 'Bob', map('theme', 'light', 'language', 'es', 'timezone', 'PST'),
     map('notifications', 'disabled', 'beta', 'false'),
     map('plan', 'free', 'region', 'us-east')),
    (3, 'Charlie', map('theme', 'dark', 'language', 'en', 'timezone', 'EST'),
     map('notifications', 'enabled', 'beta', 'true'),
     map('plan', 'premium', 'region', 'eu-west')),
    (4, 'Diana', map('theme', 'auto', 'language', 'fr', 'timezone', 'CET'),
     map('notifications', 'enabled', 'beta', 'false'),
     map('plan', 'professional', 'region', 'eu-central')),
    (5, 'Eve', map('theme', 'light', 'language', 'de', 'timezone', 'UTC'),
     map('notifications', 'disabled', 'beta', 'true'),
     map('plan', 'free', 'region', 'apac'));

-- Query 1: mapContainsKey - Find users with specific settings
SELECT '--- Users with Theme Setting (mapContainsKey) ---' AS query;
SELECT
    user_id,
    user_name,
    mapContainsKey(settings, 'theme') AS has_theme,
    mapContainsKey(settings, 'font_size') AS has_font_size,
    settings['theme'] AS theme_value
FROM user_preferences
WHERE mapContainsKey(settings, 'theme');

-- Query 2: mapContainsValue - Find users with specific values
SELECT '--- Users with Dark Theme (mapContainsValue) ---' AS query;
SELECT
    user_id,
    user_name,
    settings,
    mapContainsValue(settings, 'dark') AS has_dark_theme
FROM user_preferences
WHERE mapContainsValue(settings, 'dark');

-- Query 3: mapContainsValueLike - Pattern matching in map values
SELECT '--- Premium/Professional Plans (mapContainsValueLike) ---' AS query;
SELECT
    user_id,
    user_name,
    metadata,
    metadata['plan'] AS plan,
    mapContainsValueLike(metadata, 'premium%') OR mapContainsValueLike(metadata, 'professional%') AS is_paid_plan
FROM user_preferences
WHERE mapContainsValueLike(metadata, 'premium%') OR mapContainsValueLike(metadata, 'professional%');

-- Query 4: Combine multiple map checks
SELECT '--- Beta Users with Notifications Enabled ---' AS query;
SELECT
    user_id,
    user_name,
    features['beta'] AS beta_status,
    features['notifications'] AS notification_status
FROM user_preferences
WHERE
    mapContainsKey(features, 'beta') AND features['beta'] = 'true'
    AND mapContainsKey(features, 'notifications') AND features['notifications'] = 'enabled';

-- =====================================
-- 3. Iceberg Functions: icebergHash, icebergBucketTransform
-- =====================================

SELECT '=== Iceberg Functions ===' AS title;
SELECT
    'icebergHash - computes hash for Iceberg partitioning' AS func_1,
    'icebergBucketTransform - transforms value for Iceberg bucketing' AS func_2,
    'Used for compatible partitioning with Apache Iceberg tables' AS purpose;

-- Create sample data for Iceberg hashing
DROP TABLE IF EXISTS iceberg_compatible_data;

CREATE TABLE iceberg_compatible_data
(
    id UInt64,
    user_email String,
    product_sku String,
    order_date Date,
    amount Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY id;

INSERT INTO iceberg_compatible_data VALUES
    (1, 'alice@example.com', 'SKU-001', '2025-01-15', 99.99),
    (2, 'bob@example.com', 'SKU-002', '2025-01-15', 149.99),
    (3, 'charlie@example.com', 'SKU-003', '2025-01-16', 79.99),
    (4, 'diana@example.com', 'SKU-001', '2025-01-16', 99.99),
    (5, 'eve@example.com', 'SKU-004', '2025-01-17', 199.99),
    (6, 'frank@example.com', 'SKU-002', '2025-01-17', 149.99),
    (7, 'grace@example.com', 'SKU-005', '2025-01-18', 59.99),
    (8, 'henry@example.com', 'SKU-003', '2025-01-18', 79.99),
    (9, 'iris@example.com', 'SKU-001', '2025-01-19', 99.99),
    (10, 'jack@example.com', 'SKU-006', '2025-01-19', 299.99);

-- Query 1: icebergHash - compute hash for partitioning
SELECT '--- Iceberg Hash Examples ---' AS query;
SELECT
    user_email,
    icebergHash(user_email) AS email_hash,
    product_sku,
    icebergHash(product_sku) AS sku_hash,
    id,
    icebergHash(id) AS id_hash
FROM iceberg_compatible_data
LIMIT 5;

-- Query 2: icebergBucketTransform - bucket assignment
SELECT '--- Iceberg Bucket Transform Examples ---' AS query;
SELECT
    user_email,
    icebergBucketTransform(16, user_email) AS email_bucket_16,
    product_sku,
    icebergBucketTransform(8, product_sku) AS sku_bucket_8,
    id,
    icebergBucketTransform(4, id) AS id_bucket_4
FROM iceberg_compatible_data
LIMIT 5;

-- Query 3: Distribution analysis using buckets
SELECT '--- Bucket Distribution Analysis ---' AS query;
SELECT
    icebergBucketTransform(8, user_email) AS bucket,
    count(*) AS record_count,
    groupArray(user_email) AS users_in_bucket
FROM iceberg_compatible_data
GROUP BY bucket
ORDER BY bucket;

-- Real-world use case: Feature store with map-based attributes
DROP TABLE IF EXISTS ml_features;

CREATE TABLE ml_features
(
    feature_id UInt64,
    entity_id String,
    feature_vector Array(Float32),
    categorical_features Map(String, String),
    numerical_features Map(String, Float64),
    timestamp DateTime
)
ENGINE = MergeTree()
ORDER BY (entity_id, timestamp);

INSERT INTO ml_features VALUES
    (1, 'user_1001', [0.1, 0.2, 0.3], map('segment', 'premium', 'region', 'us'), map('lifetime_value', 1500.50, 'engagement_score', 8.5), '2025-01-15 10:00:00'),
    (2, 'user_1002', [0.4, 0.5, 0.6], map('segment', 'free', 'region', 'eu'), map('lifetime_value', 50.00, 'engagement_score', 3.2), '2025-01-15 10:05:00'),
    (3, 'user_1003', [0.7, 0.8, 0.9], map('segment', 'professional', 'region', 'apac'), map('lifetime_value', 2500.75, 'engagement_score', 9.1), '2025-01-15 10:10:00'),
    (4, 'user_1004', [0.2, 0.3, 0.4], map('segment', 'free', 'region', 'us'), map('lifetime_value', 25.00, 'engagement_score', 2.8), '2025-01-15 10:15:00'),
    (5, 'user_1005', [0.5, 0.6, 0.7], map('segment', 'premium', 'region', 'eu'), map('lifetime_value', 1800.25, 'engagement_score', 7.9), '2025-01-15 10:20:00');

-- Query: Segment analysis using map functions
SELECT '--- ML Feature Analysis by Segment ---' AS query;
SELECT
    categorical_features['segment'] AS segment,
    count(*) AS user_count,
    avg(numerical_features['lifetime_value']) AS avg_ltv,
    avg(numerical_features['engagement_score']) AS avg_engagement
FROM ml_features
WHERE mapContainsKey(categorical_features, 'segment')
GROUP BY segment
ORDER BY avg_ltv DESC;

-- Benefits summary
SELECT '=== Benefits of New Functions ===' AS info;
SELECT
    'sparseGrams: Powerful text analysis and fuzzy search capabilities' AS benefit_1,
    'mapContainsKey/Value: Efficient map filtering without extraction' AS benefit_2,
    'mapContainsValueLike: Pattern matching within map structures' AS benefit_3,
    'icebergHash/Bucket: Seamless integration with Iceberg tables' AS benefit_4,
    'All functions optimized for performance and scalability' AS benefit_5;

-- Use cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'sparseGrams: Document similarity, search indexing, text mining' AS use_case_1,
    'Map functions: Configuration filtering, metadata queries, feature stores' AS use_case_2,
    'Iceberg functions: Lakehouse integration, data partitioning, multi-engine compat' AS use_case_3,
    'Combined: Complex analytics pipelines with mixed data types' AS use_case_4;

-- Cleanup (commented out for inspection)
-- DROP TABLE ml_features;
-- DROP TABLE iceberg_compatible_data;
-- DROP TABLE user_preferences;
-- DROP TABLE text_documents;

SELECT '✅ New Functions Test Complete!' AS status;
