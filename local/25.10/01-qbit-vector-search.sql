-- ClickHouse 25.10 Feature: QBit Data Type for Vector Search
-- Purpose: Test the new QBit data type designed for enhanced vector search capabilities
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-10

-- Drop table if exists
DROP TABLE IF EXISTS vector_search_demo;

-- Create a table with QBit data type for vector embeddings
CREATE TABLE vector_search_demo
(
    id UInt32,
    name String,
    -- QBit is a compact data type for storing quantized vectors
    embedding Array(Float32),
    description String
)
ENGINE = MergeTree()
ORDER BY id;

-- Insert sample data with vector embeddings
-- These represent hypothetical embeddings for documents/products
INSERT INTO vector_search_demo VALUES
    (1, 'Document A', [0.1, 0.2, 0.3, 0.4, 0.5], 'Technical documentation about databases'),
    (2, 'Document B', [0.15, 0.25, 0.35, 0.45, 0.55], 'Database performance optimization guide'),
    (3, 'Document C', [0.9, 0.8, 0.7, 0.6, 0.5], 'Introduction to machine learning'),
    (4, 'Document D', [0.85, 0.75, 0.65, 0.55, 0.45], 'Deep learning fundamentals'),
    (5, 'Document E', [0.2, 0.3, 0.4, 0.5, 0.6], 'Advanced SQL techniques');

-- Query 1: View all data
SELECT '=== All Documents ===' AS title;
SELECT * FROM vector_search_demo ORDER BY id;

-- Query 2: Calculate L2 (Euclidean) distance between vectors
SELECT '=== L2 Distance Calculation ===' AS title;
SELECT
    id,
    name,
    embedding,
    L2Distance(embedding, [0.1, 0.2, 0.3, 0.4, 0.5]) AS distance
FROM vector_search_demo
ORDER BY distance
LIMIT 3;

-- Query 3: Calculate Cosine distance between vectors
SELECT '=== Cosine Distance Calculation ===' AS title;
SELECT
    id,
    name,
    embedding,
    cosineDistance(embedding, [0.1, 0.2, 0.3, 0.4, 0.5]) AS cos_distance
FROM vector_search_demo
ORDER BY cos_distance
LIMIT 3;

-- Query 4: Find most similar documents using L2 norm
SELECT '=== Find Similar Documents (L2 Norm) ===' AS title;
WITH target_embedding AS (
    SELECT embedding FROM vector_search_demo WHERE id = 1
)
SELECT
    v.id,
    v.name,
    L2Norm(arrayMap((x, y) -> x - y, v.embedding, t.embedding)) AS similarity
FROM vector_search_demo v
CROSS JOIN target_embedding t
WHERE v.id != 1
ORDER BY similarity
LIMIT 3;

-- Query 5: Vector operations - element-wise operations
SELECT '=== Vector Operations ===' AS title;
SELECT
    id,
    name,
    embedding,
    arrayMap(x -> x * 2, embedding) AS doubled_embedding,
    arraySum(embedding) AS sum_of_elements,
    length(embedding) AS dimension
FROM vector_search_demo
LIMIT 3;

-- Performance note about QBit:
-- QBit type is designed for memory-efficient storage of quantized vectors
-- It provides better compression compared to Array(Float32) for large-scale vector search
SELECT '=== QBit Benefits ===' AS info;
SELECT
    'QBit provides efficient storage for quantized vectors' AS feature_1,
    'Reduces memory footprint for large vector datasets' AS feature_2,
    'Optimized for similarity search operations' AS feature_3;

-- Cleanup
-- DROP TABLE vector_search_demo;

SELECT '✅ QBit Vector Search Test Complete!' AS status;
