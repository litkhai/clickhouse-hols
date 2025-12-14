-- ============================================
-- ClickHouse RBAC & Workload Management Lab - Setup
-- 1. 테스트 환경 준비 및 데이터 생성
-- ============================================

-- 실습용 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS rbac_demo;

-- 판매 데이터 테이블 (메인 트랜잭션 데이터)
CREATE TABLE IF NOT EXISTS rbac_demo.sales
(
    id UInt64,
    region String,
    product String,
    amount Decimal(18,2),
    sale_date Date,
    customer_id UInt64
) ENGINE = MergeTree()
ORDER BY (region, sale_date);

-- 고객 데이터 테이블 (민감 정보 포함)
CREATE TABLE IF NOT EXISTS rbac_demo.customers
(
    id UInt64,
    name String,
    email String,           -- 민감 정보
    phone String,           -- 민감 정보
    region String,
    created_at DateTime
) ENGINE = MergeTree()
ORDER BY id;

-- 샘플 데이터 삽입 (판매 데이터)
INSERT INTO rbac_demo.sales VALUES
    (1, 'APAC', 'Product A', 1000.00, '2024-01-15', 101),
    (2, 'APAC', 'Product B', 2500.00, '2024-01-16', 102),
    (3, 'EMEA', 'Product A', 1500.00, '2024-01-15', 103),
    (4, 'AMERICAS', 'Product C', 3000.00, '2024-01-17', 104),
    (5, 'APAC', 'Product C', 1800.00, '2024-01-18', 101),
    (6, 'EMEA', 'Product B', 2200.00, '2024-01-19', 103),
    (7, 'AMERICAS', 'Product A', 950.00, '2024-01-20', 105),
    (8, 'APAC', 'Product A', 1200.00, '2024-01-21', 102);

-- 샘플 데이터 삽입 (고객 데이터)
INSERT INTO rbac_demo.customers VALUES
    (101, 'Kim Corp', 'contact@kimcorp.com', '+82-10-1234-5678', 'APAC', now()),
    (102, 'Lee Inc', 'info@leeinc.com', '+82-10-2345-6789', 'APAC', now()),
    (103, 'Euro GmbH', 'hello@eurogmbh.de', '+49-123-456789', 'EMEA', now()),
    (104, 'US Corp', 'sales@uscorp.com', '+1-555-123-4567', 'AMERICAS', now()),
    (105, 'Americas Ltd', 'contact@americas.com', '+1-555-987-6543', 'AMERICAS', now());

-- 데이터 확인
SELECT '=== Sales Table ===' as info;
SELECT * FROM rbac_demo.sales ORDER BY sale_date;

SELECT '=== Customers Table ===' as info;
SELECT * FROM rbac_demo.customers ORDER BY id;

-- 테이블 통계
SELECT '=== Table Statistics ===' as info;
SELECT
    database,
    name as table,
    engine,
    formatReadableSize(total_bytes) as size,
    total_rows as rows
FROM system.tables
WHERE database = 'rbac_demo';
