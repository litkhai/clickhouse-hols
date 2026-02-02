-- ============================================================================
-- Bug Bounty Packet Analysis Platform - Step 1: Database Setup
-- 버그바운티 패킷 분석 플랫폼 - Step 1: 데이터베이스 설정
-- ============================================================================
-- Created: 2026-01-31
-- 작성일: 2026-01-31
-- Purpose: Create database for bug bounty packet analysis
-- 목적: 버그바운티 패킷 분석을 위한 데이터베이스 생성
-- Expected time: ~1 second
-- 예상 시간: ~1초
-- ============================================================================

-- Create database (skip if exists)
-- 데이터베이스 생성 (이미 존재하면 무시)
CREATE DATABASE IF NOT EXISTS bug_bounty;

USE bug_bounty;
