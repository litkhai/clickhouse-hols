-- ClickHouse 25.9 Feature: arrayExcept Function
-- Purpose: Test new array filtering function
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-09

-- ==========================================
-- Test 1: Basic arrayExcept Usage
-- ==========================================

SELECT '=== Test 1: Basic arrayExcept Function ===' AS title;

SELECT '\n🚀 ClickHouse 25.9 New Function: arrayExcept\nFilter arrays by removing elements from another array\n' AS info;

-- Simple example: Remove specific elements
SELECT
    [1, 2, 3, 4, 5] AS original,
    [2, 4] AS to_remove,
    arrayExcept(original, to_remove) AS result;

SELECT
    ['apple', 'banana', 'cherry', 'date'] AS fruits,
    ['banana', 'date'] AS exclude,
    arrayExcept(fruits, exclude) AS filtered_fruits;

-- ==========================================
-- Test 2: User Permissions Management
-- ==========================================

SELECT '=== Test 2: User Permissions Management ===' AS title;

DROP TABLE IF EXISTS user_permissions;

CREATE TABLE user_permissions
(
    user_id UInt32,
    user_name String,
    all_permissions Array(String),
    revoked_permissions Array(String)
)
ENGINE = MergeTree()
ORDER BY user_id;

INSERT INTO user_permissions VALUES
    (1, 'Alice', ['read', 'write', 'delete', 'admin'], ['admin']),
    (2, 'Bob', ['read', 'write', 'execute', 'debug'], ['debug', 'execute']),
    (3, 'Charlie', ['read', 'write', 'share', 'export'], ['share']),
    (4, 'David', ['read', 'write', 'delete', 'backup'], []),
    (5, 'Eve', ['read', 'admin', 'audit', 'configure'], ['admin', 'configure']);

SELECT
    user_name,
    all_permissions,
    revoked_permissions,
    arrayExcept(all_permissions, revoked_permissions) AS active_permissions
FROM user_permissions
ORDER BY user_id;

-- ==========================================
-- Test 3: E-commerce Product Features
-- ==========================================

SELECT '=== Test 3: Product Feature Filtering ===' AS title;

DROP TABLE IF EXISTS products_features;

CREATE TABLE products_features
(
    product_id UInt32,
    product_name String,
    all_features Array(String),
    unavailable_features Array(String)
)
ENGINE = MergeTree()
ORDER BY product_id;

INSERT INTO products_features VALUES
    (1, 'Laptop Pro', ['wifi', 'bluetooth', '4k-display', 'touchscreen', 'fingerprint'], ['touchscreen']),
    (2, 'Smartphone X', ['5g', 'nfc', 'wireless-charging', 'face-id', 'waterproof'], ['5g', 'face-id']),
    (3, 'Tablet Plus', ['stylus', 'keyboard', 'lte', 'gps', 'cellular'], []),
    (4, 'Smartwatch', ['heart-rate', 'gps', 'sleep-tracking', 'ecg', 'spo2'], ['ecg']),
    (5, 'Headphones', ['anc', 'bluetooth', 'multipoint', 'ldac', 'aptx'], ['ldac', 'aptx']);

SELECT
    product_name,
    all_features,
    unavailable_features,
    arrayExcept(all_features, unavailable_features) AS available_features,
    length(arrayExcept(all_features, unavailable_features)) AS feature_count
FROM products_features
ORDER BY product_id;

-- ==========================================
-- Test 4: Tag Management System
-- ==========================================

SELECT '=== Test 4: Content Tag Filtering ===' AS title;

DROP TABLE IF EXISTS content_tags;

CREATE TABLE content_tags
(
    content_id UInt32,
    title String,
    all_tags Array(String),
    banned_tags Array(String),
    publish_date Date
)
ENGINE = MergeTree()
ORDER BY content_id;

INSERT INTO content_tags VALUES
    (1, 'Tech News', ['technology', 'ai', 'sensitive', 'innovation'], ['sensitive'], today()),
    (2, 'Health Tips', ['health', 'wellness', 'medical', 'controversial'], ['controversial'], today() - 1),
    (3, 'Cooking Recipe', ['food', 'recipe', 'cooking', 'adult'], ['adult'], today() - 2),
    (4, 'Travel Guide', ['travel', 'adventure', 'sponsored', 'tourism'], ['sponsored'], today() - 3),
    (5, 'Finance News', ['finance', 'investment', 'restricted', 'money'], ['restricted'], today() - 4);

SELECT
    title,
    all_tags,
    banned_tags,
    arrayExcept(all_tags, banned_tags) AS public_tags,
    publish_date
FROM content_tags
ORDER BY publish_date DESC;

-- ==========================================
-- Test 5: Subscription Package Comparison
-- ==========================================

SELECT '=== Test 5: Subscription Package Features ===' AS title;

WITH packages AS (
    SELECT
        'Premium' AS package_name,
        ['streaming', 'downloads', 'hd', '4k', 'dolby', 'multiple-devices'] AS features
    UNION ALL
    SELECT
        'Standard' AS package_name,
        ['streaming', 'downloads', 'hd', 'multiple-devices'] AS features
    UNION ALL
    SELECT
        'Basic' AS package_name,
        ['streaming', 'sd'] AS features
)
SELECT
    p1.package_name AS from_package,
    p2.package_name AS to_package,
    p1.features AS current_features,
    p2.features AS new_features,
    arrayExcept(p1.features, p2.features) AS features_lost,
    arrayExcept(p2.features, p1.features) AS features_gained
FROM packages p1
CROSS JOIN packages p2
WHERE p1.package_name != p2.package_name
ORDER BY p1.package_name, p2.package_name;

-- ==========================================
-- Test 6: Network Security Rules
-- ==========================================

SELECT '=== Test 6: Security Rule Filtering ===' AS title;

DROP TABLE IF EXISTS security_rules;

CREATE TABLE security_rules
(
    rule_id UInt32,
    rule_name String,
    allowed_ports Array(UInt16),
    blocked_ports Array(UInt16)
)
ENGINE = MergeTree()
ORDER BY rule_id;

INSERT INTO security_rules VALUES
    (1, 'Web Server', [80, 443, 8080, 8443, 3000], [8080, 3000]),
    (2, 'Database Server', [3306, 5432, 27017, 6379, 1433], [6379]),
    (3, 'Application Server', [8000, 8001, 8002, 8003, 9000], [8003, 9000]),
    (4, 'Mail Server', [25, 587, 465, 110, 143, 993, 995], [25, 110]),
    (5, 'File Server', [20, 21, 22, 445, 2049], [20, 21, 445]);

SELECT
    rule_name,
    allowed_ports,
    blocked_ports,
    arrayExcept(allowed_ports, blocked_ports) AS active_ports,
    length(arrayExcept(allowed_ports, blocked_ports)) AS active_port_count
FROM security_rules
ORDER BY rule_id;

-- ==========================================
-- Test 7: Multiple Exclusions
-- ==========================================

SELECT '=== Test 7: Complex Array Operations ===' AS title;

SELECT
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] AS numbers,
    [2, 4, 6, 8] AS evens,
    [3, 6, 9] AS multiples_of_3,
    arrayExcept(numbers, evens) AS no_evens,
    arrayExcept(numbers, multiples_of_3) AS no_multiples_of_3,
    arrayExcept(
        arrayExcept(numbers, evens),
        multiples_of_3
    ) AS no_evens_no_multiples_of_3;

-- ==========================================
-- Test 8: Language Support Filtering
-- ==========================================

SELECT '=== Test 8: Feature Availability by Region ===' AS title;

DROP TABLE IF EXISTS regional_features;

CREATE TABLE regional_features
(
    region String,
    all_languages Array(String),
    unsupported_languages Array(String)
)
ENGINE = MergeTree()
ORDER BY region;

INSERT INTO regional_features VALUES
    ('North America', ['en', 'es', 'fr', 'de', 'ja', 'ko'], ['ja', 'ko']),
    ('Europe', ['en', 'fr', 'de', 'it', 'es', 'pt', 'pl'], ['pl']),
    ('Asia', ['en', 'ja', 'ko', 'zh', 'th', 'vi', 'id'], ['vi', 'id']),
    ('Latin America', ['es', 'pt', 'en', 'fr'], []),
    ('Middle East', ['ar', 'en', 'fa', 'he', 'tr', 'ur'], ['ur']);

SELECT
    region,
    all_languages AS potential_languages,
    unsupported_languages,
    arrayExcept(all_languages, unsupported_languages) AS supported_languages,
    length(arrayExcept(all_languages, unsupported_languages)) AS language_count
FROM regional_features
ORDER BY language_count DESC;

-- ==========================================
-- Test 9: Combining with Other Array Functions
-- ==========================================

SELECT '=== Test 9: Combining arrayExcept with Other Functions ===' AS title;

SELECT
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] AS all_numbers,
    [2, 4, 6, 8, 10] AS exclude_even,
    arrayExcept(all_numbers, exclude_even) AS odd_numbers,
    arraySum(arrayExcept(all_numbers, exclude_even)) AS sum_of_odds,
    arrayMax(arrayExcept(all_numbers, exclude_even)) AS max_odd,
    arrayMin(arrayExcept(all_numbers, exclude_even)) AS min_odd,
    length(arrayExcept(all_numbers, exclude_even)) AS count_odds;

-- ==========================================
-- Test 10: arrayExcept Benefits
-- ==========================================

SELECT '=== ClickHouse 25.9: arrayExcept Function Benefits ===' AS info;

SELECT '
🚀 arrayExcept Function Benefits:

1. Functionality:
   ✓ Remove elements from arrays efficiently
   ✓ Filter based on exclusion lists
   ✓ Cleaner syntax than manual filtering
   ✓ Works with any data type

2. Use Cases:
   - Permission management (remove revoked permissions)
   - Feature filtering (exclude unavailable features)
   - Tag management (filter banned tags)
   - Security rules (exclude blocked ports)
   - Package comparison (feature differences)

3. Syntax:
   arrayExcept(array1, array2)
   Returns: Elements in array1 that are NOT in array2

4. Performance:
   ✓ Optimized array operations
   ✓ In-memory processing
   ✓ Efficient for large arrays
   ✓ Maintains element order

5. Combination with Other Functions:
   - arraySum(arrayExcept(...))
   - arrayMax(arrayExcept(...))
   - length(arrayExcept(...))
   - Has(arrayExcept(...), element)

Before arrayExcept, filtering required complex expressions like:
arrayFilter(x -> NOT has(exclude_array, x), source_array)

Now simplified to:
arrayExcept(source_array, exclude_array)
' AS benefits;

-- Cleanup (commented out for inspection)
-- DROP TABLE user_permissions;
-- DROP TABLE products_features;
-- DROP TABLE content_tags;
-- DROP TABLE security_rules;
-- DROP TABLE regional_features;

SELECT '✅ arrayExcept Function Test Complete!' AS status;
