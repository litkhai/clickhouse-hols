-- ============================================================================
-- ClickHouse Index Granularity Point Query Benchmark - Setup
-- ClickHouse Index Granularity Point Query 벤치마크 - 설정
-- ============================================================================
-- Created: 2025-12-25
-- 작성일: 2025-12-25
-- Purpose: Create database and tables with different granularity settings
-- 목적: 다양한 granularity 설정을 가진 데이터베이스 및 테이블 생성
-- ============================================================================

-- Create test database (skip if exists)
-- 테스트 데이터베이스 생성 (이미 존재하면 무시)
CREATE DATABASE IF NOT EXISTS granularity_test;

-- Drop existing tables for clean test
-- 기존 테이블 삭제 (깨끗한 테스트를 위해)
DROP TABLE IF EXISTS granularity_test.player_g256;
DROP TABLE IF EXISTS granularity_test.player_g1024;
DROP TABLE IF EXISTS granularity_test.player_g4096;
DROP TABLE IF EXISTS granularity_test.player_g8192;

-- ============================================================================
-- 1. Granularity = 256 (Point Query Optimized)
-- 1. Granularity = 256 (Point Query 최적화)
-- ============================================================================
-- Features: Smallest granularity, best for precise point queries
-- 특징: 가장 작은 granularity, 정확한 point query에 최적
-- Trade-offs: More marks, larger index size
-- 트레이드오프: 더 많은 marks, 더 큰 인덱스 크기
-- ============================================================================

CREATE TABLE granularity_test.player_g256 (
    player_id UInt64,                           -- Player identifier / 플레이어 식별자
    player_name String,                         -- Player name / 플레이어 이름
    character_id UInt64,                        -- Character identifier / 캐릭터 식별자
    character_name String,                      -- Character name / 캐릭터 이름
    character_level UInt16,                     -- Character level / 캐릭터 레벨
    character_class LowCardinality(String),     -- Character class / 캐릭터 직업
    server_id UInt8,                            -- Server identifier / 서버 식별자
    server_name LowCardinality(String),         -- Server name / 서버 이름
    last_login_at DateTime64(3),               -- Last login timestamp / 마지막 로그인 시간
    last_ip IPv4,                               -- Last login IP / 마지막 로그인 IP
    last_device_type LowCardinality(String),    -- Device type / 디바이스 타입
    total_playtime_minutes UInt32,              -- Total playtime / 총 플레이 시간
    vip_level UInt8,                            -- VIP level / VIP 레벨
    guild_id Nullable(UInt64),                  -- Guild identifier / 길드 식별자
    guild_name Nullable(String),                -- Guild name / 길드 이름
    currency_gold UInt64,                       -- Gold currency / 골드 화폐
    currency_diamond UInt32,                    -- Diamond currency / 다이아몬드 화폐
    inventory_slots_used UInt16                 -- Inventory slots used / 사용중인 인벤토리 슬롯
)
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS index_granularity = 256;

-- ============================================================================
-- 2. Granularity = 1024
-- 2. Granularity = 1024
-- ============================================================================
-- Features: Smaller granularity, good for point queries
-- 특징: 작은 granularity, point query에 유리
-- ============================================================================

CREATE TABLE granularity_test.player_g1024 AS granularity_test.player_g256
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS index_granularity = 1024;

-- ============================================================================
-- 3. Granularity = 4096
-- 3. Granularity = 4096
-- ============================================================================
-- Features: Medium granularity, balanced performance
-- 특징: 중간 granularity, 균형잡힌 성능
-- ============================================================================

CREATE TABLE granularity_test.player_g4096 AS granularity_test.player_g256
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS index_granularity = 4096;

-- ============================================================================
-- 4. Granularity = 8192 (Default)
-- 4. Granularity = 8192 (기본값)
-- ============================================================================
-- Features: Default granularity, optimized for scan queries
-- 특징: 기본 granularity, 스캔 쿼리에 최적화
-- ============================================================================

CREATE TABLE granularity_test.player_g8192 AS granularity_test.player_g256
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS index_granularity = 8192;

-- ============================================================================
-- Verify table creation
-- 테이블 생성 확인
-- ============================================================================

SELECT
    name,
    engine,
    partition_key,
    sorting_key,
    primary_key
FROM system.tables
WHERE database = 'granularity_test'
  AND name LIKE 'player_g%'
ORDER BY name;

SELECT '✓ Setup completed successfully / 설정이 성공적으로 완료되었습니다';
