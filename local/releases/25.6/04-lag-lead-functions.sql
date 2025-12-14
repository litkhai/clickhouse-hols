-- ClickHouse 25.6 Feature: lag and lead Window Functions
-- Purpose: Test the new lag and lead window functions for SQL compatibility
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-06

-- lag() - Access data from previous rows
-- lead() - Access data from next rows
-- These functions improve SQL compatibility and simplify time-series analysis

-- Drop tables if exist
DROP TABLE IF EXISTS stock_prices;
DROP TABLE IF EXISTS user_events;
DROP TABLE IF EXISTS sales_data;

-- Create stock prices table for time series analysis
CREATE TABLE stock_prices
(
    ticker String,
    trade_date Date,
    close_price Float64,
    volume UInt64
)
ENGINE = MergeTree()
ORDER BY (ticker, trade_date);

-- Insert stock price data
INSERT INTO stock_prices VALUES
    ('AAPL', '2025-01-01', 150.00, 1000000),
    ('AAPL', '2025-01-02', 152.50, 1100000),
    ('AAPL', '2025-01-03', 151.00, 950000),
    ('AAPL', '2025-01-04', 153.75, 1200000),
    ('AAPL', '2025-01-05', 155.00, 1300000),
    ('GOOGL', '2025-01-01', 2800.00, 500000),
    ('GOOGL', '2025-01-02', 2825.00, 550000),
    ('GOOGL', '2025-01-03', 2810.00, 480000),
    ('GOOGL', '2025-01-04', 2850.00, 600000),
    ('GOOGL', '2025-01-05', 2875.00, 650000);

-- Query 1: Basic lag function - get previous day's price
SELECT '=== Basic lag Function: Previous Day Price ===' AS title;
SELECT
    ticker,
    trade_date,
    close_price,
    lag(close_price) OVER (PARTITION BY ticker ORDER BY trade_date) AS prev_day_price,
    close_price - lag(close_price) OVER (PARTITION BY ticker ORDER BY trade_date) AS price_change
FROM stock_prices
ORDER BY ticker, trade_date;

-- Query 2: Basic lead function - get next day's price
SELECT '=== Basic lead Function: Next Day Price ===' AS title;
SELECT
    ticker,
    trade_date,
    close_price,
    lead(close_price) OVER (PARTITION BY ticker ORDER BY trade_date) AS next_day_price,
    lead(close_price) OVER (PARTITION BY ticker ORDER BY trade_date) - close_price AS next_day_change
FROM stock_prices
ORDER BY ticker, trade_date;

-- Query 3: Calculate daily returns (percentage change)
SELECT '=== Daily Returns Calculation ===' AS title;
SELECT
    ticker,
    trade_date,
    close_price,
    lag(close_price) OVER (PARTITION BY ticker ORDER BY trade_date) AS prev_price,
    round(((close_price - lag(close_price) OVER (PARTITION BY ticker ORDER BY trade_date)) /
           lag(close_price) OVER (PARTITION BY ticker ORDER BY trade_date)) * 100, 2) AS daily_return_pct
FROM stock_prices
ORDER BY ticker, trade_date;

-- Query 4: lag with offset parameter (get price from 2 days ago)
SELECT '=== lag with Offset: Price from 2 Days Ago ===' AS title;
SELECT
    ticker,
    trade_date,
    close_price,
    lag(close_price, 1) OVER (PARTITION BY ticker ORDER BY trade_date) AS prev_1_day,
    lag(close_price, 2) OVER (PARTITION BY ticker ORDER BY trade_date) AS prev_2_days,
    close_price - lag(close_price, 2) OVER (PARTITION BY ticker ORDER BY trade_date) AS change_from_2_days
FROM stock_prices
ORDER BY ticker, trade_date;

-- Query 5: lead with offset and default value
SELECT '=== lead with Offset and Default ===' AS title;
SELECT
    ticker,
    trade_date,
    close_price,
    lead(close_price, 1, 0) OVER (PARTITION BY ticker ORDER BY trade_date) AS next_1_day,
    lead(close_price, 2, 0) OVER (PARTITION BY ticker ORDER BY trade_date) AS next_2_days
FROM stock_prices
ORDER BY ticker, trade_date;

-- Create user events table for funnel analysis
CREATE TABLE user_events
(
    user_id UInt32,
    event_time DateTime,
    event_type String,
    page_url String
)
ENGINE = MergeTree()
ORDER BY (user_id, event_time);

-- Insert user event data
INSERT INTO user_events VALUES
    (1, '2025-01-01 10:00:00', 'page_view', '/home'),
    (1, '2025-01-01 10:05:00', 'page_view', '/products'),
    (1, '2025-01-01 10:10:00', 'add_to_cart', '/products/item-123'),
    (1, '2025-01-01 10:15:00', 'checkout', '/checkout'),
    (1, '2025-01-01 10:20:00', 'purchase', '/confirmation'),
    (2, '2025-01-01 11:00:00', 'page_view', '/home'),
    (2, '2025-01-01 11:05:00', 'page_view', '/products'),
    (2, '2025-01-01 11:10:00', 'page_view', '/about'),
    (3, '2025-01-01 12:00:00', 'page_view', '/home'),
    (3, '2025-01-01 12:05:00', 'add_to_cart', '/products/item-456'),
    (3, '2025-01-01 12:10:00', 'purchase', '/confirmation');

-- Query 6: User journey analysis with next event
SELECT '=== User Journey Analysis ===' AS title;
SELECT
    user_id,
    event_time,
    event_type,
    page_url,
    lead(event_type) OVER (PARTITION BY user_id ORDER BY event_time) AS next_event,
    lead(event_time) OVER (PARTITION BY user_id ORDER BY event_time) AS next_event_time,
    dateDiff('second', event_time, lead(event_time) OVER (PARTITION BY user_id ORDER BY event_time)) AS seconds_to_next
FROM user_events
ORDER BY user_id, event_time;

-- Query 7: Conversion funnel - identify drop-off points
SELECT '=== Conversion Funnel Analysis ===' AS title;
SELECT
    event_type,
    count() AS event_count,
    count(DISTINCT user_id) AS unique_users,
    round(count(DISTINCT user_id) * 100.0 / (SELECT count(DISTINCT user_id) FROM user_events WHERE event_type = 'page_view'), 2) AS conversion_rate
FROM user_events
GROUP BY event_type
ORDER BY
    CASE event_type
        WHEN 'page_view' THEN 1
        WHEN 'add_to_cart' THEN 2
        WHEN 'checkout' THEN 3
        WHEN 'purchase' THEN 4
        ELSE 5
    END;

-- Query 8: Identify users who abandoned cart
SELECT '=== Cart Abandonment Detection ===' AS title;
SELECT
    user_id,
    event_time AS cart_time,
    event_type,
    lead(event_type) OVER (PARTITION BY user_id ORDER BY event_time) AS next_event,
    CASE
        WHEN event_type = 'add_to_cart' AND lead(event_type) OVER (PARTITION BY user_id ORDER BY event_time) != 'checkout'
        THEN 'ABANDONED'
        WHEN event_type = 'add_to_cart' AND lead(event_type) OVER (PARTITION BY user_id ORDER BY event_time) = 'checkout'
        THEN 'CONVERTED'
        ELSE 'N/A'
    END AS cart_status
FROM user_events
WHERE event_type = 'add_to_cart'
ORDER BY user_id, event_time;

-- Create sales data for moving averages
CREATE TABLE sales_data
(
    sale_date Date,
    region String,
    daily_revenue Float64
)
ENGINE = MergeTree()
ORDER BY (region, sale_date);

-- Insert sales data
INSERT INTO sales_data VALUES
    ('2025-01-01', 'North', 10000),
    ('2025-01-02', 'North', 12000),
    ('2025-01-03', 'North', 11000),
    ('2025-01-04', 'North', 13000),
    ('2025-01-05', 'North', 14000),
    ('2025-01-06', 'North', 12500),
    ('2025-01-07', 'North', 15000),
    ('2025-01-01', 'South', 8000),
    ('2025-01-02', 'South', 8500),
    ('2025-01-03', 'South', 9000),
    ('2025-01-04', 'South', 8800),
    ('2025-01-05', 'South', 9500),
    ('2025-01-06', 'South', 10000),
    ('2025-01-07', 'South', 10200);

-- Query 9: 3-day moving average using lag
SELECT '=== 3-Day Moving Average ===' AS title;
SELECT
    region,
    sale_date,
    daily_revenue,
    lag(daily_revenue, 1) OVER (PARTITION BY region ORDER BY sale_date) AS prev_1_day,
    lag(daily_revenue, 2) OVER (PARTITION BY region ORDER BY sale_date) AS prev_2_days,
    round((daily_revenue +
           lag(daily_revenue, 1, 0) OVER (PARTITION BY region ORDER BY sale_date) +
           lag(daily_revenue, 2, 0) OVER (PARTITION BY region ORDER BY sale_date)) / 3, 2) AS moving_avg_3d
FROM sales_data
ORDER BY region, sale_date;

-- Query 10: Trend detection - comparing to previous period
SELECT '=== Trend Detection ===' AS title;
SELECT
    region,
    sale_date,
    daily_revenue,
    lag(daily_revenue) OVER (PARTITION BY region ORDER BY sale_date) AS prev_day_revenue,
    CASE
        WHEN daily_revenue > lag(daily_revenue) OVER (PARTITION BY region ORDER BY sale_date)
        THEN 'INCREASING'
        WHEN daily_revenue < lag(daily_revenue) OVER (PARTITION BY region ORDER BY sale_date)
        THEN 'DECREASING'
        ELSE 'STABLE'
    END AS trend
FROM sales_data
ORDER BY region, sale_date;

-- Query 11: Week-over-week comparison
SELECT '=== Week-over-Week Comparison ===' AS title;
SELECT
    region,
    sale_date,
    toDayOfWeek(sale_date) AS day_of_week,
    daily_revenue,
    lag(daily_revenue, 7) OVER (PARTITION BY region ORDER BY sale_date) AS same_day_last_week,
    round(daily_revenue - lag(daily_revenue, 7, 0) OVER (PARTITION BY region ORDER BY sale_date), 2) AS wow_change
FROM sales_data
ORDER BY region, sale_date;

-- Query 12: Compare lag vs lagInFrame (similar behavior in window context)
SELECT '=== Window Frame Context ===' AS title;
SELECT
    ticker,
    trade_date,
    close_price,
    lag(close_price, 1) OVER (PARTITION BY ticker ORDER BY trade_date) AS using_lag,
    lagInFrame(close_price, 1) OVER (PARTITION BY ticker ORDER BY trade_date) AS using_lagInFrame
FROM stock_prices
ORDER BY ticker, trade_date
LIMIT 10;

-- Benefits of lag/lead functions
SELECT '=== lag/lead Function Benefits ===' AS info;
SELECT
    'Improved SQL compatibility with standard window functions' AS benefit_1,
    'Simplifies time-series analysis and trend detection' AS benefit_2,
    'Easier funnel and conversion tracking' AS benefit_3,
    'No need for self-joins for accessing adjacent rows' AS benefit_4,
    'Supports custom offsets and default values' AS benefit_5;

-- Use cases
SELECT '=== Common Use Cases ===' AS info;
SELECT
    'Stock price analysis and daily returns calculation' AS use_case_1,
    'User behavior analysis and conversion funnels' AS use_case_2,
    'Sales trend detection and forecasting' AS use_case_3,
    'Moving averages and time-series smoothing' AS use_case_4,
    'Session analysis and user journey mapping' AS use_case_5,
    'Anomaly detection by comparing to previous periods' AS use_case_6;

-- Cleanup (commented out for inspection)
-- DROP TABLE stock_prices;
-- DROP TABLE user_events;
-- DROP TABLE sales_data;

SELECT '✅ lag/lead Window Functions Test Complete!' AS status;
