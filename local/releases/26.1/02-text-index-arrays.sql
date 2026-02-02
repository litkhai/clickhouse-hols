-- ClickHouse 26.1: Text Index for Array Columns Test
-- New Feature: Text indexing capabilities extended to Array data types

-- ============================================
-- 1. Create Product Table with Tags (Array)
-- ============================================

SELECT '========== 1. Product Table with Array Tags ==========';

-- Drop existing tables
DROP TABLE IF EXISTS products_with_text_index;
DROP TABLE IF EXISTS products_no_index;

-- Create table WITH text index on array column
CREATE TABLE products_with_text_index (
    product_id UInt32,
    product_name String,
    tags Array(String),
    description String,
    price Decimal(10,2),
    created_date Date,
    INDEX tags_text_idx tags TYPE tokenbf_v1(256, 3, 0) GRANULARITY 1
) ENGINE = MergeTree()
ORDER BY (created_date, product_id)
SETTINGS index_granularity = 8192;

-- Create table WITHOUT text index for comparison
CREATE TABLE products_no_index (
    product_id UInt32,
    product_name String,
    tags Array(String),
    description String,
    price Decimal(10,2),
    created_date Date
) ENGINE = MergeTree()
ORDER BY (created_date, product_id)
SETTINGS index_granularity = 8192;

-- ============================================
-- 2. Insert Sample Data
-- ============================================

SELECT '========== 2. Inserting Sample Product Data ==========';

-- Insert diverse product data into both tables
INSERT INTO products_with_text_index VALUES
    (1, 'Laptop Pro 15', ['electronics', 'computers', 'laptop', 'portable', 'work'], 'High-performance laptop for professionals', 1299.99, '2026-01-01'),
    (2, 'Wireless Mouse', ['electronics', 'accessories', 'mouse', 'wireless', 'ergonomic'], 'Ergonomic wireless mouse', 29.99, '2026-01-02'),
    (3, 'USB-C Hub', ['electronics', 'accessories', 'usb', 'connectivity', 'adapter'], 'Multi-port USB-C hub', 49.99, '2026-01-03'),
    (4, 'Mechanical Keyboard', ['electronics', 'accessories', 'keyboard', 'mechanical', 'gaming'], 'RGB mechanical keyboard', 89.99, '2026-01-04'),
    (5, 'Monitor 27"', ['electronics', 'display', 'monitor', '4k', 'work'], '4K UHD monitor', 399.99, '2026-01-05'),
    (6, 'Webcam HD', ['electronics', 'video', 'camera', 'streaming', 'work'], 'Full HD webcam', 79.99, '2026-01-06'),
    (7, 'Desk Lamp', ['furniture', 'lighting', 'lamp', 'led', 'adjustable'], 'LED desk lamp with dimmer', 39.99, '2026-01-07'),
    (8, 'Office Chair', ['furniture', 'seating', 'chair', 'ergonomic', 'work'], 'Ergonomic office chair', 249.99, '2026-01-08'),
    (9, 'Standing Desk', ['furniture', 'desk', 'adjustable', 'ergonomic', 'work'], 'Height-adjustable standing desk', 599.99, '2026-01-09'),
    (10, 'Headphones', ['electronics', 'audio', 'headphones', 'wireless', 'noise-canceling'], 'Wireless noise-canceling headphones', 299.99, '2026-01-10'),
    (11, 'Phone Stand', ['accessories', 'phone', 'stand', 'adjustable', 'portable'], 'Adjustable phone stand', 19.99, '2026-01-11'),
    (12, 'Laptop Bag', ['accessories', 'bag', 'laptop', 'portable', 'travel'], 'Padded laptop backpack', 59.99, '2026-01-12'),
    (13, 'Cable Organizer', ['accessories', 'organization', 'cable', 'management', 'desk'], 'Cable management system', 24.99, '2026-01-13'),
    (14, 'Power Strip', ['electronics', 'power', 'surge-protector', 'usb', 'safety'], 'Smart power strip with USB', 34.99, '2026-01-14'),
    (15, 'External SSD', ['electronics', 'storage', 'ssd', 'portable', 'fast'], 'Portable external SSD 1TB', 129.99, '2026-01-15'),
    (16, 'Bluetooth Speaker', ['electronics', 'audio', 'speaker', 'bluetooth', 'portable'], 'Portable Bluetooth speaker', 79.99, '2026-01-16'),
    (17, 'Smartwatch', ['electronics', 'wearable', 'watch', 'fitness', 'smart'], 'Fitness tracking smartwatch', 199.99, '2026-01-17'),
    (18, 'Tablet 10"', ['electronics', 'tablet', 'portable', 'entertainment', 'work'], '10-inch Android tablet', 349.99, '2026-01-18'),
    (19, 'USB Flash Drive', ['electronics', 'storage', 'usb', 'portable', 'backup'], 'USB 3.0 flash drive 64GB', 14.99, '2026-01-19'),
    (20, 'Gaming Mouse Pad', ['accessories', 'gaming', 'mousepad', 'large', 'rgb'], 'Large RGB gaming mouse pad', 29.99, '2026-01-20');

-- Copy same data to table without index
INSERT INTO products_no_index SELECT * FROM products_with_text_index;

SELECT 'Inserted ' || count() || ' products' FROM products_with_text_index;

-- ============================================
-- 3. Basic Array Search with Text Index
-- ============================================

SELECT '========== 3. Basic Array Tag Search ==========';

-- Search for products with 'electronics' tag
SELECT
    product_name,
    tags,
    price
FROM products_with_text_index
WHERE has(tags, 'electronics')
ORDER BY product_id
LIMIT 5;

-- Search for products with 'work' tag
SELECT
    product_name,
    tags,
    price
FROM products_with_text_index
WHERE has(tags, 'work')
ORDER BY price DESC;

-- ============================================
-- 4. Multi-Tag Search (AND logic)
-- ============================================

SELECT '========== 4. Multi-Tag Search (AND) ==========';

-- Products that have BOTH 'electronics' AND 'portable' tags
SELECT
    product_name,
    tags,
    price
FROM products_with_text_index
WHERE has(tags, 'electronics') AND has(tags, 'portable')
ORDER BY price;

-- Products with BOTH 'ergonomic' AND 'work' tags
SELECT
    product_name,
    tags,
    price
FROM products_with_text_index
WHERE has(tags, 'ergonomic') AND has(tags, 'work')
ORDER BY product_name;

-- ============================================
-- 5. Multi-Tag Search (OR logic)
-- ============================================

SELECT '========== 5. Multi-Tag Search (OR) ==========';

-- Products that have EITHER 'gaming' OR 'rgb' tags
SELECT
    product_name,
    tags,
    price
FROM products_with_text_index
WHERE has(tags, 'gaming') OR has(tags, 'rgb')
ORDER BY product_name;

-- ============================================
-- 6. Partial Match with hasAny
-- ============================================

SELECT '========== 6. Partial Match with hasAny ==========';

-- Products matching ANY of the specified tags
SELECT
    product_name,
    tags,
    arrayIntersect(tags, ['wireless', 'bluetooth', 'portable']) AS matched_tags,
    price
FROM products_with_text_index
WHERE hasAny(tags, ['wireless', 'bluetooth', 'portable'])
ORDER BY arrayLength(matched_tags) DESC, product_name;

-- ============================================
-- 7. Pattern Matching with LIKE on Arrays
-- ============================================

SELECT '========== 7. Pattern Matching on Array Elements ==========';

-- Find products with tags starting with 'electr'
SELECT
    product_name,
    tags,
    arrayFilter(x -> x LIKE 'electr%', tags) AS matching_tags
FROM products_with_text_index
WHERE arrayExists(x -> x LIKE 'electr%', tags)
ORDER BY product_name;

-- ============================================
-- 8. Aggregation and Tag Analysis
-- ============================================

SELECT '========== 8. Tag Popularity Analysis ==========';

-- Count products by tag (explode array)
SELECT
    tag,
    count() AS product_count,
    round(avg(price), 2) AS avg_price
FROM products_with_text_index
ARRAY JOIN tags AS tag
GROUP BY tag
ORDER BY product_count DESC, tag
LIMIT 10;

-- ============================================
-- 9. Performance Comparison (EXPLAIN)
-- ============================================

SELECT '========== 9. Query Execution Plan Analysis ==========';

-- Query with text index (should use index)
EXPLAIN indexes = 1
SELECT product_name, tags
FROM products_with_text_index
WHERE has(tags, 'electronics')
FORMAT TSVRaw;

-- ============================================
-- 10. Complex Search: E-commerce Filter Example
-- ============================================

SELECT '========== 10. E-commerce Filter Simulation ==========';

-- Simulate user filtering by category and price range
SELECT
    product_name,
    tags,
    price,
    arrayStringConcat(tags, ', ') AS tag_string
FROM products_with_text_index
WHERE hasAny(tags, ['electronics', 'accessories'])
  AND price BETWEEN 20 AND 100
ORDER BY price
LIMIT 10;

-- ============================================
-- 11. Search by Multiple Categories
-- ============================================

SELECT '========== 11. Category-Based Search ==========';

-- Create category mapping
WITH category_tags AS (
    SELECT
        'Office Setup' AS category,
        ['desk', 'chair', 'lamp', 'ergonomic', 'work'] AS required_tags
    UNION ALL
    SELECT 'Gaming Gear', ['gaming', 'rgb', 'mechanical']
    UNION ALL
    SELECT 'Mobile Accessories', ['portable', 'wireless', 'phone']
)
SELECT
    ct.category,
    p.product_name,
    p.tags,
    p.price
FROM products_with_text_index p
CROSS JOIN category_tags ct
WHERE hasAny(p.tags, ct.required_tags)
ORDER BY ct.category, p.price;

-- ============================================
-- 12. Tag Co-occurrence Analysis
-- ============================================

SELECT '========== 12. Tag Co-occurrence ==========';

-- Find which tags frequently appear together
SELECT
    t1.tag AS tag1,
    t2.tag AS tag2,
    count() AS co_occurrence_count
FROM (
    SELECT product_id, tag
    FROM products_with_text_index
    ARRAY JOIN tags AS tag
) t1
INNER JOIN (
    SELECT product_id, tag
    FROM products_with_text_index
    ARRAY JOIN tags AS tag
) t2 ON t1.product_id = t2.product_id
WHERE t1.tag < t2.tag
GROUP BY tag1, tag2
ORDER BY co_occurrence_count DESC
LIMIT 10;

-- ============================================
-- 13. Full-Text Search Across Arrays and Description
-- ============================================

SELECT '========== 13. Combined Search: Tags + Description ==========';

-- Search in both tags and description
SELECT
    product_name,
    tags,
    description,
    price,
    CASE
        WHEN has(tags, 'laptop') OR description LIKE '%laptop%' THEN 'Matched Tags or Description'
        ELSE 'No Match'
    END AS match_type
FROM products_with_text_index
WHERE has(tags, 'laptop') OR description LIKE '%laptop%'
ORDER BY price;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS products_with_text_index;
-- DROP TABLE IF EXISTS products_no_index;

SELECT '========== Test Complete ==========';
SELECT 'Text index on Array columns enables efficient tag-based search!';
