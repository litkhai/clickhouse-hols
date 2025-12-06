-- ClickHouse 25.8 Feature: Temporary Data on S3
-- Purpose: Test using S3 for temporary data instead of local disks only
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-08
-- Note: This demonstrates the concept. Production use requires S3 configuration in config.xml

-- ==========================================
-- Test 1: Understanding Temporary Data
-- ==========================================

SELECT '=== Test 1: What is Temporary Data? ===' AS title;

SELECT '
📚 Temporary Data in ClickHouse:

Temporary data is created during query execution for:
1. Large JOIN operations (hash tables)
2. GROUP BY with many unique values
3. Sorting large datasets (ORDER BY)
4. Window functions
5. DISTINCT operations
6. Aggregations exceeding memory limits

Before 25.8:
- Temporary data only on local disks
- Limited by local disk space
- Potential I/O bottlenecks

ClickHouse 25.8:
✅ Can use S3 for temporary data
✅ Unlimited temporary storage capacity
✅ Better resource utilization
✅ Cost-effective for large operations
' AS explanation;

-- ==========================================
-- Test 2: Configuration Overview
-- ==========================================

SELECT '=== Test 2: S3 Temporary Data Configuration ===' AS title;

SELECT '
⚙️ Configuration in config.xml:

<storage_configuration>
    <disks>
        <s3_disk>
            <type>s3</type>
            <endpoint>https://bucket.s3.amazonaws.com/temp/</endpoint>
            <access_key_id>ACCESS_KEY</access_key_id>
            <secret_access_key>SECRET_KEY</secret_access_key>
        </s3_disk>
    </disks>
    <policies>
        <temp_policy>
            <volumes>
                <main>
                    <disk>s3_disk</disk>
                </main>
            </volumes>
        </temp_policy>
    </policies>
</storage_configuration>

Then set:
SET max_bytes_before_external_group_by = 10000000000;  -- 10GB
SET max_bytes_before_external_sort = 10000000000;       -- 10GB
SET temporary_data_policy = ''temp_policy'';

📝 Note: This lab demonstrates queries that would benefit from
S3 temporary storage. Actual S3 configuration requires cloud setup.
' AS config;

-- ==========================================
-- Test 3: Create Large Dataset for Testing
-- ==========================================

SELECT '=== Test 3: Creating Large Dataset ===' AS title;

DROP TABLE IF EXISTS user_events;
DROP TABLE IF EXISTS user_profiles;
DROP TABLE IF EXISTS product_catalog;

-- User events table (large dataset)
CREATE TABLE user_events
(
    event_id UInt64,
    event_time DateTime,
    user_id UInt64,
    event_type String,
    product_id UInt32,
    page_url String,
    session_id String,
    user_agent String,
    ip_address String,
    referrer String,
    country String,
    city String,
    device_type String,
    browser String,
    os String
)
ENGINE = MergeTree()
ORDER BY (event_time, user_id);

-- Insert large dataset (500,000 events)
INSERT INTO user_events
SELECT
    number AS event_id,
    now() - INTERVAL (number % 2592000) SECOND AS event_time,
    (number % 50000) + 1 AS user_id,
    ['page_view', 'click', 'scroll', 'form_submit', 'video_play'][1 + (number % 5)] AS event_type,
    (number % 10000) + 1 AS product_id,
    concat('/page/', toString(number % 1000)) AS page_url,
    concat('session_', toString(number % 25000)) AS session_id,
    concat('Mozilla/5.0 Agent/', toString(number % 100)) AS user_agent,
    concat('192.168.', toString((number % 255) + 1), '.', toString((number % 255) + 1)) AS ip_address,
    ['Google', 'Facebook', 'Direct', 'Email', 'Twitter'][1 + (number % 5)] AS referrer,
    ['USA', 'UK', 'Germany', 'France', 'Japan', 'Canada', 'Australia', 'Brazil'][1 + (number % 8)] AS country,
    concat('City_', toString((number % 500) + 1)) AS city,
    ['Desktop', 'Mobile', 'Tablet'][1 + (number % 3)] AS device_type,
    ['Chrome', 'Safari', 'Firefox', 'Edge', 'Opera'][1 + (number % 5)] AS browser,
    ['Windows', 'macOS', 'Linux', 'iOS', 'Android'][1 + (number % 5)] AS os
FROM numbers(500000);

-- User profiles table
CREATE TABLE user_profiles
(
    user_id UInt64,
    username String,
    email String,
    signup_date Date,
    country String,
    age UInt8,
    subscription_tier String,
    lifetime_value Decimal(10, 2),
    is_active UInt8
)
ENGINE = MergeTree()
ORDER BY user_id;

-- Insert user profiles
INSERT INTO user_profiles
SELECT
    number + 1 AS user_id,
    concat('user_', toString(number + 1)) AS username,
    concat('user', toString(number + 1), '@example.com') AS email,
    today() - INTERVAL (number % 1000) DAY AS signup_date,
    ['USA', 'UK', 'Germany', 'France', 'Japan', 'Canada', 'Australia', 'Brazil'][1 + (number % 8)] AS country,
    (number % 60) + 18 AS age,
    ['Free', 'Basic', 'Premium', 'Enterprise'][1 + (number % 4)] AS subscription_tier,
    round((number % 1000) + 50.00, 2) AS lifetime_value,
    if(number % 10 < 8, 1, 0) AS is_active
FROM numbers(50000);

-- Product catalog table
CREATE TABLE product_catalog
(
    product_id UInt32,
    product_name String,
    category String,
    subcategory String,
    brand String,
    price Decimal(10, 2),
    cost Decimal(10, 2),
    inventory_quantity UInt32,
    rating Decimal(3, 2)
)
ENGINE = MergeTree()
ORDER BY product_id;

-- Insert products
INSERT INTO product_catalog
SELECT
    number + 1 AS product_id,
    concat('Product_', toString(number + 1)) AS product_name,
    ['Electronics', 'Clothing', 'Home', 'Sports', 'Books', 'Toys', 'Food'][1 + (number % 7)] AS category,
    concat('SubCat_', toString(number % 20)) AS subcategory,
    concat('Brand_', toString(number % 100)) AS brand,
    round((number % 500) + 10.00, 2) AS price,
    round(((number % 500) + 10.00) * 0.6, 2) AS cost,
    (number % 1000) + 10 AS inventory_quantity,
    round(3.0 + (number % 20) * 0.1, 2) AS rating
FROM numbers(10000);

SELECT '✅ Test datasets created' AS status;
SELECT formatReadableQuantity(count()) || ' events' AS user_events FROM user_events;
SELECT formatReadableQuantity(count()) || ' profiles' AS user_profiles FROM user_profiles;
SELECT formatReadableQuantity(count()) || ' products' AS product_catalog FROM product_catalog;

-- ==========================================
-- Test 4: Large JOIN Operation (Uses Temp Data)
-- ==========================================

SELECT '=== Test 4: Large JOIN Operation ===' AS title;
SELECT '(This type of query benefits from S3 temporary data)' AS note;

-- Large JOIN between events, users, and products
-- This would use temporary storage for hash tables
SELECT
    up.subscription_tier,
    up.country,
    count() AS events,
    count(DISTINCT ue.user_id) AS active_users,
    count(DISTINCT ue.session_id) AS sessions,
    round(avg(pc.price), 2) AS avg_product_price
FROM user_events ue
JOIN user_profiles up ON ue.user_id = up.user_id
JOIN product_catalog pc ON ue.product_id = pc.product_id
WHERE up.is_active = 1
GROUP BY up.subscription_tier, up.country
ORDER BY events DESC
LIMIT 20;

SELECT '✅ Large JOIN completed (would use temp storage for large datasets)' AS result;

-- ==========================================
-- Test 5: Heavy Aggregation with GROUP BY
-- ==========================================

SELECT '=== Test 5: Heavy Aggregation with Many Groups ===' AS title;
SELECT '(May spill to temp storage if groups exceed memory)' AS note;

-- High-cardinality GROUP BY
SELECT
    toDate(event_time) AS date,
    toHour(event_time) AS hour,
    country,
    city,
    device_type,
    browser,
    event_type,
    count() AS events,
    count(DISTINCT user_id) AS unique_users,
    count(DISTINCT session_id) AS unique_sessions
FROM user_events
GROUP BY date, hour, country, city, device_type, browser, event_type
ORDER BY events DESC
LIMIT 30;

SELECT '✅ Heavy aggregation completed' AS result;

-- ==========================================
-- Test 6: Large DISTINCT Operation
-- ==========================================

SELECT '=== Test 6: Large DISTINCT Operation ===' AS title;

-- Count distinct users by various dimensions
SELECT
    country,
    count(DISTINCT user_id) AS unique_users,
    count(DISTINCT session_id) AS unique_sessions,
    count(DISTINCT ip_address) AS unique_ips,
    count(DISTINCT user_agent) AS unique_agents,
    count() AS total_events
FROM user_events
GROUP BY country
ORDER BY unique_users DESC;

SELECT '✅ DISTINCT operation completed' AS result;

-- ==========================================
-- Test 7: Complex Window Functions
-- ==========================================

SELECT '=== Test 7: Window Functions (May Use Temp Storage) ===' AS title;

-- Window functions with large partitions
WITH user_event_stats AS (
    SELECT
        user_id,
        event_time,
        event_type,
        row_number() OVER (PARTITION BY user_id ORDER BY event_time) AS event_sequence,
        count() OVER (PARTITION BY user_id) AS user_total_events,
        first_value(event_type) OVER (PARTITION BY user_id ORDER BY event_time) AS first_event,
        last_value(event_type) OVER (PARTITION BY user_id ORDER BY event_time ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_event
    FROM user_events
    LIMIT 10000
)
SELECT
    user_id,
    user_total_events,
    first_event,
    last_event,
    count() AS rows_analyzed
FROM user_event_stats
GROUP BY user_id, user_total_events, first_event, last_event
ORDER BY user_total_events DESC
LIMIT 20;

SELECT '✅ Window functions completed' AS result;

-- ==========================================
-- Test 8: Large ORDER BY Operation
-- ==========================================

SELECT '=== Test 8: Large Sorting Operation ===' AS title;
SELECT '(Large sorts may spill to temp storage)' AS note;

-- Sort large dataset
SELECT
    user_id,
    count() AS events,
    count(DISTINCT session_id) AS sessions,
    count(DISTINCT product_id) AS products_viewed,
    min(event_time) AS first_seen,
    max(event_time) AS last_seen,
    arrayStringConcat(groupArray(DISTINCT event_type), ', ') AS event_types
FROM user_events
GROUP BY user_id
ORDER BY events DESC
LIMIT 100;

SELECT '✅ Large sort completed' AS result;

-- ==========================================
-- Test 9: Session Analysis (Complex Query)
-- ==========================================

SELECT '=== Test 9: Complex Session Analysis ===' AS title;

-- User session funnel analysis
WITH session_events AS (
    SELECT
        ue.session_id,
        ue.user_id,
        up.subscription_tier,
        up.country,
        count() AS event_count,
        countIf(ue.event_type = 'page_view') AS page_views,
        countIf(ue.event_type = 'click') AS clicks,
        countIf(ue.event_type = 'form_submit') AS conversions,
        min(ue.event_time) AS session_start,
        max(ue.event_time) AS session_end,
        dateDiff('second', min(ue.event_time), max(ue.event_time)) AS session_duration
    FROM user_events ue
    JOIN user_profiles up ON ue.user_id = up.user_id
    GROUP BY ue.session_id, ue.user_id, up.subscription_tier, up.country
)
SELECT
    subscription_tier,
    country,
    count() AS sessions,
    round(avg(event_count), 2) AS avg_events_per_session,
    round(avg(session_duration), 2) AS avg_duration_seconds,
    sum(page_views) AS total_page_views,
    sum(clicks) AS total_clicks,
    sum(conversions) AS total_conversions,
    round(sum(conversions) / sum(page_views) * 100, 2) AS conversion_rate
FROM session_events
GROUP BY subscription_tier, country
ORDER BY sessions DESC
LIMIT 20;

-- ==========================================
-- Test 10: Product Performance Analysis
-- ==========================================

SELECT '=== Test 10: Product Performance with Multiple JOINs ===' AS title;

-- Comprehensive product analysis
SELECT
    pc.category,
    pc.subcategory,
    count(DISTINCT pc.product_id) AS products,
    count(DISTINCT ue.user_id) AS unique_viewers,
    count() AS total_views,
    round(avg(pc.price), 2) AS avg_price,
    round(avg(pc.rating), 2) AS avg_rating,
    sum(pc.inventory_quantity) AS total_inventory
FROM user_events ue
JOIN product_catalog pc ON ue.product_id = pc.product_id
WHERE ue.event_type = 'page_view'
GROUP BY pc.category, pc.subcategory
ORDER BY total_views DESC
LIMIT 30;

-- ==========================================
-- Test 11: User Cohort Analysis
-- ==========================================

SELECT '=== Test 11: User Cohort Retention Analysis ===' AS title;

-- Cohort analysis by signup month
WITH user_cohorts AS (
    SELECT
        user_id,
        toStartOfMonth(signup_date) AS cohort_month,
        subscription_tier,
        country
    FROM user_profiles
),
cohort_activity AS (
    SELECT
        uc.cohort_month,
        uc.subscription_tier,
        toStartOfMonth(ue.event_time) AS activity_month,
        count(DISTINCT ue.user_id) AS active_users,
        count() AS events
    FROM user_events ue
    JOIN user_cohorts uc ON ue.user_id = uc.user_id
    GROUP BY uc.cohort_month, uc.subscription_tier, activity_month
)
SELECT
    cohort_month,
    subscription_tier,
    activity_month,
    active_users,
    events,
    round(events / active_users, 2) AS events_per_user
FROM cohort_activity
ORDER BY cohort_month DESC, subscription_tier, activity_month DESC
LIMIT 30;

-- ==========================================
-- Performance Summary
-- ==========================================

SELECT '=== Temporary Data on S3 Summary ===' AS title;

SELECT '
✅ Temporary Data on S3 Features in ClickHouse 25.8:

1. Unlimited Temporary Storage:
   - Use S3 instead of local disks
   - No local disk space limitations
   - Cost-effective for large operations

2. Operations That Benefit:
   ✓ Large JOINs (hash table spillover)
   ✓ High-cardinality GROUP BY
   ✓ Large ORDER BY operations
   ✓ DISTINCT with many values
   ✓ Window functions with large partitions
   ✓ Complex aggregations

3. Configuration:
   - Set temporary_data_policy in config.xml
   - Configure S3 disk for temp data
   - Set memory thresholds for spillover

4. Performance Characteristics:
   - Automatic spillover when memory exceeded
   - Transparent to queries
   - Optimized I/O patterns for S3
   - Background cleanup of temp data

5. Use Cases:
   📊 Ad-hoc analytics on large datasets
   📊 Complex multi-table JOINs
   📊 High-cardinality aggregations
   📊 Data exploration and discovery
   📊 ML feature engineering
   📊 Data quality checks on full datasets

6. Benefits:
   ✅ Scale beyond local disk limits
   ✅ Better resource utilization
   ✅ Cost-effective (S3 cheaper than local SSD)
   ✅ No manual temp data management
   ✅ Improved query success rate

💡 Best Practices:
- Set appropriate memory thresholds
- Monitor S3 costs for temp data
- Use for analytical workloads
- Consider data locality for hot paths
- Clean up temp data regularly

🎯 Configuration Example:
SET max_bytes_before_external_group_by = 10000000000;
SET max_bytes_before_external_sort = 10000000000;
SET temporary_data_policy = ''s3_temp_policy'';
' AS summary;

-- Optional: Cleanup (commented out by default)
-- DROP TABLE IF EXISTS user_events;
-- DROP TABLE IF EXISTS user_profiles;
-- DROP TABLE IF EXISTS product_catalog;
-- SELECT '🧹 Cleanup completed' AS status;
