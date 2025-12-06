-- ============================================================================
-- Customer 360 Lab Step 6: Data Management and Security
-- Customer 360 실습 Step 6: 데이터 관리 및 보안
-- ============================================================================
-- Created: 2025-12-06
-- 작성일: 2025-12-06
-- Purpose: Data management, security, and compliance operations
-- 목적: 데이터 관리, 보안 및 규정 준수 작업
-- ============================================================================

-- ============================================================================
-- 6.1 Partition Management
-- 6.1 파티션 관리
-- ============================================================================

-- Check partition list / 파티션 목록 확인
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
  AND active = 1
ORDER BY table, partition DESC;

-- Drop specific month partition (e.g., data older than 90 days)
-- 특정 월 파티션 삭제 (예: 90일 이전 데이터)
-- Warning: Use carefully in production / 주의: 실제 프로덕션에서는 신중하게 사용
-- ALTER TABLE customer360.transactions
-- DROP PARTITION '202508';

-- ============================================================================
-- 6.2 TTL (Time To Live) Configuration
-- 6.2 TTL (Time To Live) 설정
-- ============================================================================

-- Set 90-day TTL on event data (auto-delete after 90 days)
-- 이벤트 데이터에 90일 TTL 설정 (90일 후 자동 삭제)
ALTER TABLE customer360.customer_events
MODIFY TTL event_timestamp + INTERVAL 90 DAY;

-- TTL-based auto-aggregation (monthly rollup after 1 year)
-- TTL 기반 자동 집계 (1년 후 월별로 롤업)
-- Automatically aggregate old detailed data to save storage
-- 오래된 상세 데이터를 자동으로 집계하여 저장 공간 절약
ALTER TABLE customer360.transactions
MODIFY TTL
    transaction_date + INTERVAL 365 DAY
    GROUP BY customer_id, toYYYYMM(transaction_date)
    SET
        transaction_id = any(transaction_id),
        total_amount = sum(total_amount),
        transaction_count = count();

-- ============================================================================
-- 6.3 Role-Based Access Control (RBAC)
-- 6.3 역할 기반 접근 제어 (RBAC)
-- ============================================================================

-- Create read-only role for marketing team
-- 마케팅 팀용 읽기 전용 역할 생성
CREATE ROLE IF NOT EXISTS marketing_read;

-- Grant SELECT permissions on marketing-related tables
-- 마케팅 관련 테이블에 대한 SELECT 권한 부여
GRANT SELECT ON customer360.customers TO marketing_read;
GRANT SELECT ON customer360.transactions TO marketing_read;
GRANT SELECT ON customer360.campaign_responses TO marketing_read;

-- Example: Assign role to user / 사용자에게 역할 할당 예시
-- CREATE USER marketing_user IDENTIFIED BY 'password';
-- GRANT marketing_read TO marketing_user;

-- ============================================================================
-- 6.4 Data Masking Views
-- 6.4 데이터 마스킹 뷰
-- ============================================================================

-- Create view with masked personal information
-- 개인정보를 마스킹한 뷰 생성
CREATE OR REPLACE VIEW customer360.customers_masked AS
SELECT
    customer_id,
    concat(substring(email, 1, 3), '***@', splitByChar('@', email)[2]) AS email_masked,
    concat(substring(phone, 1, 3), '-****-', substring(phone, -4)) AS phone_masked,
    first_name,
    'REDACTED' AS last_name,
    toYear(date_of_birth) AS birth_year,
    customer_segment,
    lifetime_value
FROM customer360.customers;

-- Query masked view / 마스킹된 뷰 조회
SELECT * FROM customer360.customers_masked LIMIT 10;

-- ============================================================================
-- 6.5 Row Level Security (RLS)
-- 6.5 행 수준 보안 (Row Level Security)
-- ============================================================================

-- Restrict Korea regional manager to view only Korean customers
-- 한국 지역 관리자는 한국 고객만 조회 가능하도록 제한
-- CREATE ROW POLICY IF NOT EXISTS korea_only ON customer360.customers
-- FOR SELECT
-- USING country = 'KR'
-- TO regional_manager_kr;

-- Restrict US regional manager to view only US customers
-- 미국 지역 관리자는 미국 고객만 조회 가능
-- CREATE ROW POLICY IF NOT EXISTS us_only ON customer360.customers
-- FOR SELECT
-- USING country = 'US'
-- TO regional_manager_us;

-- ============================================================================
-- 6.6 GDPR Compliance - Personal Data Management
-- 6.6 GDPR 준수 - 개인정보 관리
-- ============================================================================

-- Completely delete personal information for specific customer
-- 특정 고객의 개인정보 완전 삭제
-- ALTER TABLE customer360.customers
-- DELETE WHERE customer_id = 12345;

-- Delete from related tables as well / 관련 테이블에서도 삭제
-- ALTER TABLE customer360.transactions DELETE WHERE customer_id = 12345;
-- ALTER TABLE customer360.customer_events DELETE WHERE customer_id = 12345;

-- Anonymize personal information (instead of deletion)
-- 개인정보 익명화 (삭제 대신 익명화)
-- ALTER TABLE customer360.customers
-- UPDATE
--     email = concat('deleted_', toString(customer_id), '@anonymized.com'),
--     phone = 'DELETED',
--     first_name = 'DELETED',
--     last_name = 'DELETED'
-- WHERE customer_id = 12345;

-- ============================================================================
-- 6.7 Audit Log Query
-- 6.7 감사 로그 조회
-- ============================================================================

-- View query history accessing customer table
-- 고객 테이블에 접근한 쿼리 이력 조회
SELECT
    user,
    query_start_time,
    query_duration_ms,
    type,
    read_rows,
    result_rows,
    substring(query, 1, 200) AS query_preview
FROM system.query_log
WHERE type = 'QueryFinish'
  AND has(tables, 'customer360.customers')
  AND query_start_time >= today()
ORDER BY query_start_time DESC
LIMIT 20;

-- Specific user activity history / 특정 사용자의 활동 이력
-- SELECT
--     query_start_time,
--     query_duration_ms,
--     read_rows,
--     substring(query, 1, 100) AS query_preview
-- FROM system.query_log
-- WHERE user = 'marketing_user'
--   AND query_start_time >= today() - INTERVAL 7 DAY
-- ORDER BY query_start_time DESC
-- LIMIT 50;

-- ============================================================================
-- 6.8 Backup and Restore
-- 6.8 백업 및 복구
-- ============================================================================

-- Backup table to file (INTO OUTFILE) / 테이블을 파일로 백업
-- SELECT * FROM customer360.customers
-- INTO OUTFILE '/backup/customers.csv'
-- FORMAT CSVWithNames;

-- Restore from backup (FROM INFILE) / 백업에서 복구
-- INSERT INTO customer360.customers
-- FROM INFILE '/backup/customers.csv'
-- FORMAT CSVWithNames;

-- ============================================================================
-- 6.9 System Monitoring
-- 6.9 시스템 모니터링
-- ============================================================================

-- Total disk usage for database / 데이터베이스 전체 디스크 사용량
SELECT
    database,
    formatReadableSize(sum(bytes_on_disk)) AS total_size,
    count() AS table_count
FROM system.parts
WHERE active = 1
  AND database = 'customer360'
GROUP BY database;

-- Monitor running queries / 실행 중인 쿼리 모니터링
SELECT
    query_id,
    user,
    elapsed,
    formatReadableSize(memory_usage) AS memory,
    formatReadableSize(read_bytes) AS read_data,
    read_rows,
    substring(query, 1, 100) AS query_preview
FROM system.processes
WHERE query != ''
ORDER BY elapsed DESC;

-- Query statistics by table (last 1 hour) / 테이블별 쿼리 통계 (최근 1시간)
SELECT
    tables[1] AS table_name,
    count() AS query_count,
    round(avg(query_duration_ms), 2) AS avg_duration_ms,
    formatReadableSize(sum(read_bytes)) AS total_read,
    sum(read_rows) AS total_rows_read
FROM system.query_log
WHERE type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 1 HOUR
  AND database = 'customer360'
GROUP BY table_name
ORDER BY query_count DESC;
