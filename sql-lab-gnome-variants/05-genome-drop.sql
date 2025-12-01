-- ================================================
-- 데이터베이스 및 테이블 삭제
-- Drop Database and Tables
-- ================================================

-- ================================================
-- 경고: 이 스크립트는 모든 genome 데이터를 삭제합니다!
-- WARNING: This script will delete all genome data!
-- ================================================

-- ================================================
-- 1. Materialized View 삭제
-- 1. Drop Materialized View
-- Note: MV를 먼저 삭제해야 합니다 (의존성 때문에)
-- Note: Drop MV first due to dependency
-- ================================================
DROP VIEW IF EXISTS genome.gene_summary;

-- ================================================
-- 2. 메인 테이블 삭제
-- 2. Drop Main Table
-- ================================================
DROP TABLE IF EXISTS genome.variants_full;

-- ================================================
-- 3. 데이터베이스 삭제
-- 3. Drop Database
-- ================================================
DROP DATABASE IF EXISTS genome;

-- ================================================
-- 확인 쿼리
-- Verification Queries
-- ================================================

-- 데이터베이스 목록 확인
-- Check database list
SHOW DATABASES;

-- genome 데이터베이스가 존재하는지 확인
-- Verify if genome database exists
SELECT name
FROM system.databases
WHERE name = 'genome';
