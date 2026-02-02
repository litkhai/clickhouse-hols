-- ============================================================================
-- Security Traffic Analysis Platform - Step 7: Utility Functions & Views
-- 보안 트래픽 분석 플랫폼 - Step 7: 유틸리티 함수 및 뷰
-- ============================================================================
-- Created: 2026-01-31
-- 작성일: 2026-01-31
-- Purpose: Create reusable utility functions and convenience views
-- 목적: 재사용 가능한 유틸리티 함수 및 편의 뷰 생성
-- Expected time: ~2-3 seconds
-- 예상 시간: ~2-3초
-- ============================================================================

USE security_traffic_analysis;

-- ============================================================================
-- 7.1 PII Masking Functions (Reusable)
-- 7.1 민감정보 마스킹 함수 모음 (재사용 가능)
-- ============================================================================
-- Features: Reusable functions for masking various PII types
-- 특징: 다양한 PII 유형을 마스킹하는 재사용 가능한 함수
-- ============================================================================

-- JWT 토큰 마스킹
-- 사용: SELECT maskJWT(response_body) FROM http_packets
CREATE FUNCTION IF NOT EXISTS maskJWT AS (text) -> 
    replaceRegexpAll(text, 
        'eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}', 
        '[JWT_REDACTED]');

-- 이메일 마스킹
CREATE FUNCTION IF NOT EXISTS maskEmail AS (text) -> 
    replaceRegexpAll(text, 
        '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}', 
        '[EMAIL_REDACTED]');

-- 한국 전화번호 마스킹
CREATE FUNCTION IF NOT EXISTS maskPhoneKR AS (text) -> 
    replaceRegexpAll(text, 
        '01[0-9]-?[0-9]{3,4}-?[0-9]{4}', 
        '[PHONE_REDACTED]');

-- 신용카드 마스킹
CREATE FUNCTION IF NOT EXISTS maskCreditCard AS (text) -> 
    replaceRegexpAll(text, 
        '\\b[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\\b', 
        '[CARD_REDACTED]');

-- API Key 마스킹 (JSON 필드)
CREATE FUNCTION IF NOT EXISTS maskApiKey AS (text) -> 
    replaceRegexpAll(text, 
        '"[Aa]pi[_-]?[Kk]ey"\\s*:\\s*"[^"]+"', 
        '"api_key":"[REDACTED]"');

-- 종합 마스킹 (모든 PII 유형)
CREATE FUNCTION IF NOT EXISTS maskAllPII AS (text) -> 
    maskCreditCard(maskPhoneKR(maskEmail(maskApiKey(maskJWT(text)))));


-- ============================================================================
-- 7.2 Threat Score Calculation Functions
-- 7.2 위협 점수 계산 함수
-- ============================================================================
-- Features: Functions to calculate threat scores for different attack types
-- 특징: 다양한 공격 유형에 대한 위협 점수 계산 함수
-- ============================================================================

-- Bruteforce 점수 계산
CREATE FUNCTION IF NOT EXISTS calcBruteforceScore AS 
    (request_count, unique_endpoints, auth_error_count) -> 
    multiIf(
        request_count > 100 AND unique_endpoints < 5, 0.95,
        request_count > 50 AND unique_endpoints < 3, 0.8,
        auth_error_count > 20, 0.7,
        request_count > 30 AND (auth_error_count / request_count) > 0.5, 0.6,
        0.1
    );

-- Scanner 점수 계산
CREATE FUNCTION IF NOT EXISTS calcScannerScore AS 
    (unique_endpoints, request_count, admin_attempts) -> 
    multiIf(
        unique_endpoints > 50 AND request_count > 100, 0.95,
        unique_endpoints > 30, 0.75,
        admin_attempts > 10, 0.7,
        unique_endpoints > 20, 0.5,
        0.1
    );


-- ============================================================================
-- 7.3 Convenience Views (Frequently Used Queries)
-- 7.3 편의 뷰 (자주 사용하는 쿼리)
-- ============================================================================
-- Features: Pre-defined views for common monitoring and analysis tasks
-- 특징: 일반적인 모니터링 및 분석 작업을 위한 사전 정의 뷰
-- ============================================================================

-- 실시간 트래픽 모니터링 뷰
CREATE VIEW IF NOT EXISTS v_realtime_traffic AS
SELECT 
    toStartOfMinute(timestamp) as minute,
    count() as requests,
    uniq(session_id) as sessions,
    uniq(source_ip) as unique_ips,
    countIf(response_status >= 400) as errors,
    round(avg(response_time_ms), 2) as avg_response_ms
FROM http_packets
WHERE timestamp >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute DESC;


-- 활성 위협 뷰
CREATE VIEW IF NOT EXISTS v_active_threats AS
SELECT 
    source_ip_hash,
    participant_id,
    sum(request_count) as total_requests,
    max(bruteforce_score) as bruteforce,
    max(scanner_score) as scanner,
    max(enumeration_score) as enumeration,
    max(edos_score) as edos,
    greatest(
        max(bruteforce_score),
        max(scanner_score),
        max(enumeration_score),
        max(edos_score)
    ) as max_threat
FROM attack_detection_agg
WHERE window_start >= now() - INTERVAL 30 MINUTE
GROUP BY source_ip_hash, participant_id
HAVING max_threat > 0.5;


-- PII 노출 요약 뷰
CREATE VIEW IF NOT EXISTS v_pii_summary AS
SELECT 
    toDate(timestamp) as date,
    pii_type,
    severity,
    count() as count,
    uniq(session_id) as sessions,
    uniq(report_id) as reports
FROM pii_exposure_log
WHERE event_date >= today() - INTERVAL 30 DAY
GROUP BY date, pii_type, severity;


-- 리포트 상태 뷰
CREATE VIEW IF NOT EXISTS v_report_status AS
SELECT 
    report_id,
    triage_status,
    estimated_severity,
    total_requests,
    crash_count,
    has_pii_exposure,
    first_seen,
    last_seen,
    dateDiff('hour', first_seen, last_seen) as duration_hours
FROM triage_results
WHERE report_id != ''
ORDER BY 
    multiIf(
        estimated_severity = 'CRITICAL', 1,
        estimated_severity = 'HIGH', 2,
        estimated_severity = 'MEDIUM_HIGH', 3,
        4
    ),
    last_seen DESC;


-- ----------------------------------------------------------------------------
-- 4. 데이터 정리 프로시저 (수동 실행용)
-- ----------------------------------------------------------------------------

-- 만료된 차단 비활성화
-- 주기적으로 실행 권장
CREATE VIEW IF NOT EXISTS v_expired_blocks AS
SELECT 
    source_ip_hash,
    participant_id,
    blocked_at,
    expires_at,
    block_reason
FROM block_list
WHERE is_active = 1 AND expires_at < now();

-- 만료된 차단 비활성화 실행 (수동)
-- ALTER TABLE block_list UPDATE is_active = 0 WHERE is_active = 1 AND expires_at < now();


-- ----------------------------------------------------------------------------
-- 5. 통계 테이블 (시간대별 집계용)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hourly_stats
(
    hour DateTime,
    
    -- 트래픽
    total_packets UInt64,
    unique_sessions UInt32,
    unique_ips UInt32,
    
    -- 응답 상태
    status_2xx UInt64,
    status_4xx UInt64,
    status_5xx UInt64,
    
    -- 성능
    avg_response_ms Float32,
    p95_response_ms Float32,
    p99_response_ms Float32,
    
    -- 위협
    threat_detections UInt32,
    blocked_ips UInt32,
    
    -- PII
    pii_exposures UInt32
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY hour
TTL hour + INTERVAL 90 DAY;


-- 시간대별 통계 집계 MV
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_hourly_stats
REFRESH EVERY 10 MINUTE
TO hourly_stats
AS
SELECT 
    toStartOfHour(timestamp) as hour,
    
    count() as total_packets,
    uniq(session_id) as unique_sessions,
    uniq(source_ip) as unique_ips,
    
    countIf(response_status >= 200 AND response_status < 300) as status_2xx,
    countIf(response_status >= 400 AND response_status < 500) as status_4xx,
    countIf(response_status >= 500) as status_5xx,
    
    avg(response_time_ms) as avg_response_ms,
    quantile(0.95)(response_time_ms) as p95_response_ms,
    quantile(0.99)(response_time_ms) as p99_response_ms,
    
    0 as threat_detections,
    0 as blocked_ips,
    
    countIf(
        match(response_body, 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+')
        OR match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}')
    ) as pii_exposures

FROM http_packets
WHERE timestamp >= now() - INTERVAL 24 HOUR
GROUP BY hour;
