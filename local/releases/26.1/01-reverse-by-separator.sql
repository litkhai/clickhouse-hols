-- ClickHouse 26.1: reverseBySeparator Function Test
-- New Feature: Function that reverses the order of substrings separated by a specified separator

-- ============================================
-- 1. Basic Usage Examples
-- ============================================

SELECT '========== 1. Basic reverseBySeparator Examples ==========';

-- URL path reversal
SELECT
    '/users/john/documents/file.pdf' AS original_path,
    reverseBySeparator('/', original_path) AS reversed_path;

-- Domain name reversal (useful for reverse DNS)
SELECT
    'www.example.com' AS domain,
    reverseBySeparator('.', domain) AS reversed_domain;

-- CSV column reordering
SELECT
    'first,second,third,fourth' AS csv_line,
    reverseBySeparator(',', csv_line) AS reversed_csv;

-- Breadcrumb navigation
SELECT
    'Home > Products > Electronics > Laptops' AS breadcrumb,
    reverseBySeparator(' > ', breadcrumb) AS reversed_breadcrumb;

-- File path reversal
SELECT
    'C:\\Users\\John\\Documents\\file.txt' AS windows_path,
    reverseBySeparator('\\', windows_path) AS reversed_windows_path;

-- ============================================
-- 2. Practical Use Cases
-- ============================================

SELECT '========== 2. Practical Use Cases ==========';

-- Create a test table for URL analysis
DROP TABLE IF EXISTS url_logs;
CREATE TABLE url_logs (
    event_time DateTime,
    user_id UInt32,
    url_path String
) ENGINE = MergeTree()
ORDER BY (event_time, user_id);

-- Insert sample data
INSERT INTO url_logs VALUES
    ('2026-01-15 10:00:00', 101, '/api/v2/users/profile'),
    ('2026-01-15 10:01:00', 102, '/api/v2/products/electronics/laptops'),
    ('2026-01-15 10:02:00', 103, '/blog/2026/01/clickhouse-features'),
    ('2026-01-15 10:03:00', 104, '/docs/guides/getting-started/installation'),
    ('2026-01-15 10:04:00', 105, '/api/v1/orders/12345/status');

-- Use reverseBySeparator to extract API version from paths
SELECT
    url_path,
    reverseBySeparator('/', url_path) AS reversed,
    splitByChar('/', url_path)[2] AS api_version
FROM url_logs
WHERE url_path LIKE '/api/%'
ORDER BY event_time;

-- ============================================
-- 3. Log Format Transformation
-- ============================================

SELECT '========== 3. Log Format Transformation ==========';

-- Create log table
DROP TABLE IF EXISTS application_logs;
CREATE TABLE application_logs (
    log_time DateTime,
    log_level String,
    module_path String,
    message String
) ENGINE = MergeTree()
ORDER BY log_time;

-- Insert sample logs with module paths
INSERT INTO application_logs VALUES
    ('2026-01-15 10:00:00', 'INFO', 'com.example.service.user.authentication', 'User logged in'),
    ('2026-01-15 10:01:00', 'ERROR', 'com.example.service.payment.processor', 'Payment failed'),
    ('2026-01-15 10:02:00', 'WARN', 'com.example.database.connection.pool', 'Connection timeout'),
    ('2026-01-15 10:03:00', 'DEBUG', 'com.example.cache.redis.client', 'Cache miss');

-- Convert Java package naming to filesystem-like path
SELECT
    module_path,
    replaceAll(module_path, '.', '/') AS filesystem_path,
    reverseBySeparator('.', module_path) AS reversed_package,
    splitByChar('.', reverseBySeparator('.', module_path))[1] AS most_specific_module
FROM application_logs
ORDER BY log_time;

-- ============================================
-- 4. Reverse DNS and Network Analysis
-- ============================================

SELECT '========== 4. Reverse DNS and Network Analysis ==========';

-- Create network table
DROP TABLE IF EXISTS dns_queries;
CREATE TABLE dns_queries (
    query_time DateTime,
    domain String,
    query_type String,
    response_code UInt16
) ENGINE = MergeTree()
ORDER BY query_time;

-- Insert DNS queries
INSERT INTO dns_queries VALUES
    ('2026-01-15 10:00:00', 'www.clickhouse.com', 'A', 200),
    ('2026-01-15 10:01:00', 'api.github.com', 'A', 200),
    ('2026-01-15 10:02:00', 'docs.python.org', 'A', 200),
    ('2026-01-15 10:03:00', 'blog.example.co.uk', 'A', 200);

-- Reverse domain for grouping and analysis
SELECT
    domain,
    reverseBySeparator('.', domain) AS reversed_domain,
    splitByChar('.', domain)[-1] AS tld,
    splitByChar('.', reverseBySeparator('.', domain))[1] AS tld_check
FROM dns_queries
ORDER BY reversed_domain;

-- ============================================
-- 5. Hierarchical Data Navigation
-- ============================================

SELECT '========== 5. Hierarchical Data Navigation ==========';

-- Create category hierarchy table
DROP TABLE IF EXISTS product_categories;
CREATE TABLE product_categories (
    product_id UInt32,
    category_path String,
    product_name String
) ENGINE = MergeTree()
ORDER BY product_id;

-- Insert hierarchical category data
INSERT INTO product_categories VALUES
    (1, 'Electronics/Computers/Laptops', 'MacBook Pro'),
    (2, 'Electronics/Mobile/Smartphones', 'iPhone 15'),
    (3, 'Home/Kitchen/Appliances', 'Coffee Maker'),
    (4, 'Books/Technology/Programming', 'Learning SQL'),
    (5, 'Electronics/Audio/Headphones', 'AirPods Pro');

-- Reverse category paths for bottom-up analysis
SELECT
    product_name,
    category_path,
    reverseBySeparator('/', category_path) AS reversed_path,
    splitByChar('/', category_path)[1] AS top_category,
    splitByChar('/', reverseBySeparator('/', category_path))[1] AS bottom_category
FROM product_categories
ORDER BY top_category, product_name;

-- ============================================
-- 6. Performance Comparison
-- ============================================

SELECT '========== 6. Performance Characteristics ==========';

-- Show that reverseBySeparator preserves empty segments
SELECT
    'a//b///c' AS original,
    reverseBySeparator('/', original) AS reversed,
    splitByChar('/', original) AS split_array,
    splitByChar('/', reversed) AS reversed_array;

-- Combining with other string functions
SELECT
    '/api/v2/users/profile/settings' AS path,
    reverseBySeparator('/', path) AS reversed,
    arrayStringConcat(arrayReverse(splitByChar('/', path)), '/') AS manual_reverse,
    reversed = manual_reverse AS methods_match;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS url_logs;
-- DROP TABLE IF EXISTS application_logs;
-- DROP TABLE IF EXISTS dns_queries;
-- DROP TABLE IF EXISTS product_categories;

SELECT '========== Test Complete ==========';
