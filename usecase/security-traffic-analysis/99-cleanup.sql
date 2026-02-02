-- ============================================================================
-- Bug Bounty Packet Analysis Platform - Cleanup Script
-- 버그바운티 패킷 분석 플랫폼 - 정리 스크립트
-- ============================================================================
-- Created: 2026-01-31
-- 작성일: 2026-01-31
-- Purpose: Reset and cleanup demo environment
-- 목적: 데모 환경 초기화 및 정리
-- ⚠️ WARNING: This script will delete all data!
-- ⚠️ 주의: 이 스크립트는 모든 데이터를 삭제합니다!
-- Expected time: ~2-3 seconds
-- 예상 시간: ~2-3초
-- ============================================================================

USE bug_bounty;

-- ============================================================================
-- 1. Drop Materialized Views (Required before dropping tables)
-- 1. Materialized Views 삭제 (테이블 삭제 전 필수)
-- ============================================================================

DROP VIEW IF EXISTS mv_anonymize_packets;
DROP VIEW IF EXISTS mv_pii_exposure_log;
DROP VIEW IF EXISTS mv_attack_detection;
DROP VIEW IF EXISTS mv_auto_triage;
DROP VIEW IF EXISTS mv_auto_block;
DROP VIEW IF EXISTS mv_daily_summary;
DROP VIEW IF EXISTS mv_hourly_stats;


-- ============================================================================
-- 2. Drop Regular Views
-- 2. 일반 Views 삭제
-- ============================================================================

DROP VIEW IF EXISTS v_realtime_traffic;
DROP VIEW IF EXISTS v_active_threats;
DROP VIEW IF EXISTS v_pii_summary;
DROP VIEW IF EXISTS v_report_status;
DROP VIEW IF EXISTS v_expired_blocks;


-- ============================================================================
-- 3. Drop Functions
-- 3. Functions 삭제
-- ============================================================================

DROP FUNCTION IF EXISTS maskJWT;
DROP FUNCTION IF EXISTS maskEmail;
DROP FUNCTION IF EXISTS maskPhoneKR;
DROP FUNCTION IF EXISTS maskCreditCard;
DROP FUNCTION IF EXISTS maskApiKey;
DROP FUNCTION IF EXISTS maskAllPII;
DROP FUNCTION IF EXISTS calcBruteforceScore;
DROP FUNCTION IF EXISTS calcScannerScore;


-- ============================================================================
-- 4. Drop Tables
-- 4. 테이블 삭제
-- ============================================================================

DROP TABLE IF EXISTS http_packets;
DROP TABLE IF EXISTS http_packets_anonymized;
DROP TABLE IF EXISTS attack_detection_agg;
DROP TABLE IF EXISTS triage_results;
DROP TABLE IF EXISTS block_list;
DROP TABLE IF EXISTS pii_exposure_log;
DROP TABLE IF EXISTS daily_summary;
DROP TABLE IF EXISTS hourly_stats;


-- ============================================================================
-- 5. Drop Database (Optional)
-- 5. 데이터베이스 삭제 (선택사항)
-- ============================================================================
-- ⚠️ WARNING: The command below will delete the entire database!
-- ⚠️ 주의: 아래 명령은 전체 데이터베이스를 삭제합니다!
-- Uncomment to execute / 실행하려면 주석 해제
-- DROP DATABASE IF EXISTS bug_bounty;


-- ============================================================================
-- Verification
-- 검증
-- ============================================================================

SELECT '✅ Cleanup completed!' as status;
