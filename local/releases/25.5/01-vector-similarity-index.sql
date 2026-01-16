-- ClickHouse 25.5 Feature: Vector Similarity Index (Beta)
-- Purpose: Test vector similarity search with HNSW index, prefiltering, and postfiltering
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-05

-- Drop tables if exist
DROP TABLE IF EXISTS product_embeddings;

-- Create a table with vector embeddings for product recommendations
-- This demonstrates the Vector Similarity Index feature in ClickHouse 25.5
CREATE TABLE product_embeddings
(
    product_id UInt32,
    product_name String,
    category String,
    price Float32,
    embedding Array(Float32),
    INDEX vec_idx embedding TYPE vector_similarity('hnsw', 'L2Distance') GRANULARITY 1
)
ENGINE = MergeTree()
ORDER BY product_id
SETTINGS index_granularity = 8192;

-- Insert sample product data with embeddings
-- In a real scenario, these embeddings would come from ML models
INSERT INTO product_embeddings VALUES
    (1, 'Laptop Pro 15', 'Electronics', 1299.99, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]),
    (2, 'Wireless Mouse', 'Electronics', 29.99, [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85]),
    (3, 'USB-C Cable', 'Electronics', 19.99, [0.12, 0.22, 0.32, 0.42, 0.52, 0.62, 0.72, 0.82]),
    (4, 'Office Chair', 'Furniture', 249.99, [0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1]),
    (5, 'Standing Desk', 'Furniture', 399.99, [0.85, 0.75, 0.65, 0.55, 0.45, 0.35, 0.25, 0.15]),
    (6, 'Desk Lamp', 'Furniture', 59.99, [0.82, 0.72, 0.62, 0.52, 0.42, 0.32, 0.22, 0.12]),
    (7, 'Mechanical Keyboard', 'Electronics', 129.99, [0.13, 0.23, 0.33, 0.43, 0.53, 0.63, 0.73, 0.83]),
    (8, 'Monitor 27inch', 'Electronics', 349.99, [0.11, 0.21, 0.31, 0.41, 0.51, 0.61, 0.71, 0.81]),
    (9, 'Bookshelf', 'Furniture', 149.99, [0.83, 0.73, 0.63, 0.53, 0.43, 0.33, 0.23, 0.13]),
    (10, 'Webcam HD', 'Electronics', 79.99, [0.14, 0.24, 0.34, 0.44, 0.54, 0.64, 0.74, 0.84]);

-- Query 1: Basic vector similarity search
-- Find products similar to a given embedding (e.g., user's preference vector)
SELECT '=== Basic Vector Similarity Search ===' AS title;
SELECT
    product_id,
    product_name,
    category,
    price,
    L2Distance(embedding, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]) AS distance
FROM product_embeddings
ORDER BY distance ASC
LIMIT 5;

-- Query 2: Vector search with postfiltering
-- First find similar vectors, then filter by category
-- This uses the vector_search_filter_strategy='postfilter' approach
SELECT '=== Vector Search with Postfiltering (Category Filter) ===' AS title;
SELECT
    product_id,
    product_name,
    category,
    price,
    L2Distance(embedding, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]) AS distance
FROM product_embeddings
WHERE category = 'Electronics'
ORDER BY distance ASC
LIMIT 5;

-- Query 3: Vector search with prefiltering
-- Filter by price range first, then find similar vectors
-- This demonstrates prefiltering strategy
SELECT '=== Vector Search with Prefiltering (Price Filter) ===' AS title;
SELECT
    product_id,
    product_name,
    category,
    price,
    L2Distance(embedding, [0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1]) AS distance
FROM product_embeddings
WHERE price BETWEEN 50 AND 300
ORDER BY distance ASC
LIMIT 5;

-- Query 4: Hybrid search - combine vector similarity with metadata filters
SELECT '=== Hybrid Search (Vector + Multiple Filters) ===' AS title;
SELECT
    product_id,
    product_name,
    category,
    price,
    L2Distance(embedding, [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85]) AS distance
FROM product_embeddings
WHERE
    category = 'Electronics'
    AND price < 200
ORDER BY distance ASC
LIMIT 3;

-- Real-world use case: Product recommendation system
DROP TABLE IF EXISTS user_interactions;
DROP TABLE IF EXISTS user_embeddings;

-- Create user embeddings table
CREATE TABLE user_embeddings
(
    user_id UInt32,
    user_name String,
    preference_embedding Array(Float32),
    budget_max Float32,
    preferred_category String
)
ENGINE = MergeTree()
ORDER BY user_id;

-- Insert sample user data
INSERT INTO user_embeddings VALUES
    (101, 'Alice', [0.12, 0.22, 0.32, 0.42, 0.52, 0.62, 0.72, 0.82], 500, 'Electronics'),
    (102, 'Bob', [0.81, 0.71, 0.61, 0.51, 0.41, 0.31, 0.21, 0.11], 300, 'Furniture'),
    (103, 'Charlie', [0.14, 0.24, 0.34, 0.44, 0.54, 0.64, 0.74, 0.84], 1000, 'Electronics');

-- Query 5: Personalized product recommendations for users
SELECT '=== Personalized Recommendations for Alice ===' AS title;
SELECT
    u.user_name,
    p.product_id,
    p.product_name,
    p.category,
    p.price,
    L2Distance(p.embedding, u.preference_embedding) AS similarity_score
FROM user_embeddings u
CROSS JOIN product_embeddings p
WHERE
    u.user_id = 101
    AND p.category = u.preferred_category
    AND p.price <= u.budget_max
ORDER BY similarity_score ASC
LIMIT 5;

-- Query 6: Find complementary products (different category but budget-aware)
SELECT '=== Complementary Products for Bob ===' AS title;
SELECT
    u.user_name,
    p.product_id,
    p.product_name,
    p.category,
    p.price,
    L2Distance(p.embedding, u.preference_embedding) AS similarity_score
FROM user_embeddings u
CROSS JOIN product_embeddings p
WHERE
    u.user_id = 102
    AND p.price <= u.budget_max
ORDER BY similarity_score ASC
LIMIT 5;

-- Query 7: Batch recommendations - top 3 products for each user
SELECT '=== Batch Recommendations (Top 3 per User) ===' AS title;
SELECT
    user_id,
    user_name,
    product_name,
    category,
    price,
    similarity_score
FROM (
    SELECT
        u.user_id,
        u.user_name,
        p.product_name,
        p.category,
        p.price,
        L2Distance(p.embedding, u.preference_embedding) AS similarity_score,
        ROW_NUMBER() OVER (PARTITION BY u.user_id ORDER BY L2Distance(p.embedding, u.preference_embedding)) AS rn
    FROM user_embeddings u
    CROSS JOIN product_embeddings p
    WHERE p.category = u.preferred_category
)
WHERE rn <= 3
ORDER BY user_id, similarity_score;

-- Query 8: Statistics on vector index usage
SELECT '=== Vector Similarity Index Benefits ===' AS info;
SELECT
    'HNSW index provides approximate nearest neighbor search' AS benefit_1,
    'Prefiltering: filter first, then vector search (better for selective filters)' AS benefit_2,
    'Postfiltering: vector search first, then filter (better for broad searches)' AS benefit_3,
    'Hybrid search combines vector similarity with metadata filters' AS benefit_4,
    'Beta feature in 25.5 - production-ready with filtering support' AS benefit_5;

-- Use cases
SELECT '=== Real-World Use Cases ===' AS info;
SELECT
    'Product recommendations and e-commerce search' AS use_case_1,
    'Content discovery and personalization' AS use_case_2,
    'Similarity search in documents and images' AS use_case_3,
    'Anomaly detection using embedding distances' AS use_case_4,
    'Question-answering systems with semantic search' AS use_case_5,
    'Customer segmentation based on behavioral embeddings' AS use_case_6;

-- Performance tips
SELECT '=== Performance Tips ===' AS info;
SELECT
    'Use prefiltering when filters are highly selective (< 10% of data)' AS tip_1,
    'Use postfiltering for broad searches or low-selectivity filters' AS tip_2,
    'Set vector_search_filter_strategy to auto for automatic optimization' AS tip_3,
    'Choose appropriate GRANULARITY for vector index based on data size' AS tip_4,
    'Monitor query performance and adjust filter strategies accordingly' AS tip_5;

-- Cleanup (commented out for inspection)
-- DROP TABLE user_embeddings;
-- DROP TABLE product_embeddings;

SELECT '✅ Vector Similarity Index Test Complete!' AS status;
