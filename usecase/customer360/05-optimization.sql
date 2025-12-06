-- ============================================================================
-- Customer 360 Lab Step 5: Materialized Views and Optimization
-- Customer 360 실습 Step 5: Materialized View 및 최적화
-- ============================================================================
-- Created: 2025-12-06
-- 작성일: 2025-12-06
-- Purpose: Performance optimization using materialized views and monitoring
-- 목적: Materialized View와 모니터링을 활용한 성능 최적화
-- ============================================================================

-- ============================================================================
-- 5.1 Materialized View for Real-time Customer KPIs
-- 5.1 실시간 고객 KPI를 위한 Materialized View
-- ============================================================================
-- Pre-aggregate transaction data by day for improved query performance
-- 거래 데이터를 일별로 사전 집계하여 쿼리 성능 향상
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS customer360.customer_kpi_mv
ENGINE = AggregatingMergeTree()
ORDER BY (customer_id, date)
AS
SELECT
    customer_id,
    toDate(transaction_date) AS date,
    countState() AS transaction_count,
    sumState(total_amount) AS total_revenue,
    avgState(total_amount) AS avg_transaction_value,
    maxState(transaction_date) AS last_transaction_time
FROM customer360.transactions
WHERE transaction_type = 'purchase'
GROUP BY customer_id, date;

-- ============================================================================
-- 5.2 Materialized View Query Example
-- 5.2 Materialized View 쿼리 예시
-- ============================================================================
-- High-speed aggregation queries using pre-aggregated data
-- MV를 활용한 고속 집계 쿼리
-- ============================================================================

SELECT
    customer_id,
    date,
    countMerge(transaction_count) AS transactions,
    sumMerge(total_revenue) AS revenue,
    avgMerge(avg_transaction_value) AS avg_value
FROM customer360.customer_kpi_mv
WHERE customer_id < 1000
GROUP BY customer_id, date
ORDER BY revenue DESC
LIMIT 20;

-- ============================================================================
-- 5.3 Performance and Metadata Analysis
-- 5.3 성능 및 메타데이터 분석
-- ============================================================================
-- Analyze storage and compression efficiency
-- 스토리지 및 압축 효율 분석
-- ============================================================================

SELECT
    table,
    formatReadableSize(total_bytes) AS compressed_size,
    formatReadableSize(total_bytes_uncompressed) AS uncompressed_size,
    round(total_bytes_uncompressed / nullIf(total_bytes, 0), 2) AS compression_ratio,
    formatReadableQuantity(total_rows) AS row_count,
    parts AS part_count,
    active_parts,
    formatReadableQuantity(total_marks) AS mark_count
FROM system.tables
WHERE database = 'customer360'
ORDER BY total_bytes DESC;

-- ============================================================================
-- 5.4 Overall Dataset Summary
-- 5.4 전체 데이터셋 요약
-- ============================================================================
-- Check total database size and compression ratio
-- 전체 데이터베이스의 크기와 압축률 확인
-- ============================================================================

SELECT
    'Total Data Summary' AS metric_category,
    formatReadableQuantity(
        (SELECT count() FROM customer360.customers) +
        (SELECT count() FROM customer360.transactions) +
        (SELECT count() FROM customer360.customer_events) +
        (SELECT count() FROM customer360.support_tickets) +
        (SELECT count() FROM customer360.campaign_responses) +
        (SELECT count() FROM customer360.product_reviews)
    ) AS total_records,

    formatReadableSize(
        (SELECT sum(total_bytes) FROM system.tables WHERE database = 'customer360')
    ) AS total_compressed_size,

    formatReadableSize(
        (SELECT sum(total_bytes_uncompressed) FROM system.tables WHERE database = 'customer360')
    ) AS total_uncompressed_size,

    round(
        (SELECT sum(total_bytes_uncompressed) FROM system.tables WHERE database = 'customer360') /
        nullIf((SELECT sum(total_bytes) FROM system.tables WHERE database = 'customer360'), 0),
        2
    ) AS overall_compression_ratio;

-- ============================================================================
-- 5.5 Query Execution Plan Analysis
-- 5.5 쿼리 실행 계획 분석
-- ============================================================================
-- Analyze execution plan and cost estimation for complex JOIN queries
-- 복잡한 JOIN 쿼리의 실행 계획 및 비용 추정
-- ============================================================================

EXPLAIN ESTIMATE
SELECT
    c.customer_id,
    c.email,
    c.customer_segment,
    count(DISTINCT t.transaction_id) AS total_transactions,
    sum(t.total_amount) AS total_spent,
    count(DISTINCT e.session_id) AS total_sessions,
    count(DISTINCT s.ticket_id) AS total_tickets,
    count(DISTINCT pr.review_id) AS total_reviews
FROM customer360.customers c
LEFT JOIN customer360.transactions t ON c.customer_id = t.customer_id
LEFT JOIN customer360.customer_events e ON c.customer_id = e.customer_id
LEFT JOIN customer360.support_tickets s ON c.customer_id = s.customer_id
LEFT JOIN customer360.product_reviews pr ON c.customer_id = pr.customer_id
WHERE c.customer_id < 1000000
GROUP BY c.customer_id, c.email, c.customer_segment;

-- ============================================================================
-- 5.6 Table Optimization
-- 5.6 테이블 최적화
-- ============================================================================
-- Merge partitions and clean up data
-- 파티션 병합 및 데이터 정리
-- ============================================================================

OPTIMIZE TABLE customer360.transactions FINAL;

-- ============================================================================
-- 5.7 Partition List Check
-- 5.7 파티션 목록 확인
-- ============================================================================
-- View currently created partitions
-- 현재 생성된 파티션 확인
-- ============================================================================

SELECT
    table,
    partition,
    name,
    formatReadableSize(bytes_on_disk) AS size,
    rows,
    min_date,
    max_date
FROM system.parts
WHERE database = 'customer360'
  AND table = 'transactions'
  AND active = 1
ORDER BY partition DESC, name;

-- ============================================================================
-- 5.8 Query Performance Monitoring
-- 5.8 쿼리 성능 모니터링
-- ============================================================================
-- Check performance metrics of recently executed queries
-- 최근 실행된 쿼리의 성능 지표 확인
-- ============================================================================

SELECT
    type,
    event_time,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read_size,
    result_rows,
    formatReadableSize(memory_usage) AS memory,
    substring(query, 1, 100) AS query_preview
FROM system.query_log
WHERE type = 'QueryFinish'
  AND database = 'customer360'
  AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY query_duration_ms DESC
LIMIT 10;
