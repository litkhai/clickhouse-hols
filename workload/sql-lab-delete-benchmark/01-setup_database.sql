-- ============================================================================
-- ClickHouse DELETE Mechanism Benchmark - Setup Database
-- ClickHouse DELETE 메커니즘 벤치마크 - 데이터베이스 설정
-- ============================================================================
-- Created: 2025-12-01
-- 작성일: 2025-12-01
-- Purpose: Create database and tables for testing
-- 목적: 테스트를 위한 데이터베이스 및 테이블 생성
-- ============================================================================

-- Create database (skip if exists)
-- 데이터베이스 생성 (이미 존재하면 무시)
CREATE DATABASE IF NOT EXISTS delete_test;

-- Drop existing tables for clean test
-- 기존 테이블 삭제 (깨끗한 테스트를 위해)
DROP TABLE IF EXISTS delete_test.alter_delete_table;
DROP TABLE IF EXISTS delete_test.replacing_merge_table;
DROP TABLE IF EXISTS delete_test.collapsing_merge_table;

-- ============================================================================
-- 1. ALTER DELETE Table (SharedMergeTree)
-- 1. ALTER DELETE 테이블 (SharedMergeTree)
-- ============================================================================
-- Features: Physical delete, mutation-based, complete data removal
-- 특징: 물리적 삭제, mutation 사용, 완전한 데이터 제거
-- ============================================================================

CREATE TABLE delete_test.alter_delete_table
(
    user_id UInt64,                    -- User identifier / 사용자 식별자
    event_time DateTime,               -- Event timestamp / 이벤트 타임스탬프
    event_type String,                 -- Event type / 이벤트 타입
    value Float64,                     -- Event value / 이벤트 값
    status String                      -- Event status / 이벤트 상태
)
ENGINE = SharedMergeTree()
PARTITION BY toYYYYMM(event_time)     -- Monthly partitioning / 월별 파티셔닝
ORDER BY (user_id, event_time)        -- Sorting key / 정렬 키
SETTINGS index_granularity = 8192;    -- Index granularity / 인덱스 granularity

-- ============================================================================
-- 2. ReplacingMergeTree Table
-- 2. ReplacingMergeTree 테이블
-- ============================================================================
-- Features: Logical delete, version-based deduplication, is_deleted flag
-- 특징: 논리적 삭제, version으로 중복 제거, is_deleted 플래그
-- Requires FINAL modifier for accurate results
-- 정확한 결과를 위해 FINAL modifier 필요
-- Supports history tracking
-- 히스토리 추적 가능
-- ============================================================================

CREATE TABLE delete_test.replacing_merge_table
(
    user_id UInt64,                    -- User identifier / 사용자 식별자
    event_time DateTime,               -- Event timestamp / 이벤트 타임스탬프
    event_type String,                 -- Event type / 이벤트 타입
    value Float64,                     -- Event value / 이벤트 값
    status String,                     -- Event status / 이벤트 상태
    version UInt64,                    -- Version for deduplication (higher = newer) / 버전 관리용 (높을수록 최신)
    is_deleted UInt8 DEFAULT 0         -- Delete flag (0=active, 1=deleted) / 삭제 플래그 (0=활성, 1=삭제)
)
ENGINE = SharedReplacingMergeTree(version)  -- Version column for deduplication / version 컬럼으로 중복 제거
PARTITION BY toYYYYMM(event_time)           -- Monthly partitioning / 월별 파티셔닝
ORDER BY (user_id, event_time)              -- Sorting key / 정렬 키
SETTINGS index_granularity = 8192;          -- Index granularity / 인덱스 granularity

-- ============================================================================
-- 3. CollapsingMergeTree Table
-- 3. CollapsingMergeTree 테이블
-- ============================================================================
-- Features: Logical delete, sign column for collapsing, aggregation with sum(sign)
-- 특징: 논리적 삭제, sign 컬럼으로 상쇄, sum(sign)으로 집계
-- Order dependency: sign=-1 must come after sign=1
-- 순서 의존성: sign=-1이 sign=1 이후에 와야 함
-- ============================================================================

CREATE TABLE delete_test.collapsing_merge_table
(
    user_id UInt64,                    -- User identifier / 사용자 식별자
    event_time DateTime,               -- Event timestamp / 이벤트 타임스탬프
    event_type String,                 -- Event type / 이벤트 타입
    value Float64,                     -- Event value / 이벤트 값
    status String,                     -- Event status / 이벤트 상태
    sign Int8                          -- Sign column (1=insert, -1=delete) / 사인 컬럼 (1=추가, -1=삭제)
)
ENGINE = SharedCollapsingMergeTree(sign)    -- Sign column for collapsing / sign 컬럼으로 상쇄
PARTITION BY toYYYYMM(event_time)           -- Monthly partitioning / 월별 파티셔닝
ORDER BY (user_id, event_time)              -- Sorting key / 정렬 키
SETTINGS index_granularity = 8192;          -- Index granularity / 인덱스 granularity

-- ============================================================================
-- Verify table creation
-- 테이블 생성 확인
-- ============================================================================

SELECT 
    database,
    name,
    engine,
    total_rows,
    total_bytes
FROM system.tables
WHERE database = 'delete_test'
ORDER BY name;

-- ============================================================================
-- Completion message
-- 완료 메시지
-- ============================================================================
SELECT 'Database and tables created successfully!' as status;
SELECT '데이터베이스와 테이블이 성공적으로 생성되었습니다!' as status_kr;
