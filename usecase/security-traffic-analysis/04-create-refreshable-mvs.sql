-- ============================================================================
-- Security Traffic Analysis Platform - Step 4: Refreshable Materialized Views
-- 보안 트래픽 분석 플랫폼 - Step 4: 주기적 갱신 Materialized Views 생성
-- ============================================================================
-- Created: 2026-01-31
-- 작성일: 2026-01-31
-- Purpose: Create periodically refreshed aggregation and analysis views
-- 목적: 주기적으로 갱신되는 집계/분석 뷰 생성 (ClickHouse Cloud 기능)
-- Expected time: ~2-3 seconds
-- 예상 시간: ~2-3초
-- ============================================================================

USE security_traffic_analysis;

-- ============================================================================
-- 4.1 Attack Detection Aggregation MV (Refresh every 1 minute)
-- 4.1 공격 탐지 집계 MV (1분마다 갱신)
-- ============================================================================
-- Features: Analyze traffic patterns in 1-minute windows to detect attacks
-- 특징: 1분 윈도우로 트래픽 패턴을 분석하여 공격 징후 탐지
-- Refresh: Every 1 minute / 갱신 주기: 1분마다
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_attack_detection
REFRESH EVERY 1 MINUTE
TO attack_detection_agg
AS
SELECT 
    toStartOfMinute(timestamp) as window_start,
    toStartOfMinute(timestamp) + INTERVAL 1 MINUTE as window_end,
    hex(cityHash64(source_ip)) as source_ip_hash,
    participant_id,
    
    -- 기본 집계 메트릭
    count() as request_count,
    uniq(request_uri) as unique_endpoints,
    countIf(response_status >= 400) as error_count,
    sum(response_time_ms) as total_response_time,
    sum(content_length) as total_content_length,
    
    -- ========================================
    -- Bruteforce 점수 계산
    -- ========================================
    -- 특징: 같은 엔드포인트에 반복 요청 (로그인 시도 등)
    multiIf(
        -- 100회 이상 요청 + 5개 미만 엔드포인트 = 매우 높은 위험
        count() > 100 AND uniq(request_uri) < 5, 0.95,
        -- 50회 이상 요청 + 3개 미만 엔드포인트 = 높은 위험
        count() > 50 AND uniq(request_uri) < 3, 0.8,
        -- 30회 이상 요청 + 인증 엔드포인트 타겟팅
        count() > 30 AND countIf(request_uri LIKE '%login%' OR request_uri LIKE '%auth%') > 20, 0.7,
        -- 높은 에러율 + 반복 요청
        count() > 20 AND (countIf(response_status IN (401, 403)) / count()) > 0.5, 0.6,
        0.1
    ) as bruteforce_score,
    
    -- ========================================
    -- Scanner 점수 계산
    -- ========================================
    -- 특징: 다양한 엔드포인트를 광범위하게 탐색
    multiIf(
        -- 50개 이상 고유 엔드포인트 + 100회 이상 요청
        uniq(request_uri) > 50 AND count() > 100, 0.95,
        -- 30개 이상 고유 엔드포인트
        uniq(request_uri) > 30, 0.75,
        -- 관리자 경로 다수 접근 시도
        countIf(request_uri LIKE '%admin%' OR request_uri LIKE '%config%' OR request_uri LIKE '%.env%') > 10, 0.7,
        -- 20개 이상 엔드포인트 + 404 에러 다수
        uniq(request_uri) > 20 AND countIf(response_status = 404) > 15, 0.6,
        0.1
    ) as scanner_score,
    
    -- ========================================
    -- Enumeration 점수 계산
    -- ========================================
    -- 특징: 순차적 ID나 파라미터로 데이터 열거 시도
    multiIf(
        -- 사용자 ID 열거 패턴 (20회 이상)
        countIf(match(request_uri, '/api/users/[0-9]+')) > 20, 0.9,
        -- 일반 ID 열거 패턴 (50회 이상)
        countIf(match(request_uri, '/api/.*/[0-9]+')) > 50, 0.8,
        -- 페이지 파라미터 열거
        countIf(match(request_uri, '[?&](page|id|user_id|item_id)=[0-9]+')) > 30, 0.7,
        -- 403 에러와 함께 ID 패턴 접근
        countIf(response_status = 403 AND match(request_uri, '/[0-9]+')) > 10, 0.6,
        0.1
    ) as enumeration_score,
    
    -- ========================================
    -- EDoS (Economic Denial of Service) 점수 계산
    -- ========================================
    -- 특징: 리소스 소모 공격 (느린 응답 유발, 대용량 요청)
    multiIf(
        -- 평균 응답시간 5초 이상 + 50회 이상 요청
        (sum(response_time_ms) / count()) > 5000 AND count() > 50, 0.95,
        -- 총 컨텐츠 100MB 이상 요청
        sum(content_length) > 100000000, 0.85,
        -- 평균 응답시간 3초 이상 + 대용량 요청
        (sum(response_time_ms) / count()) > 3000 AND sum(content_length) > 50000000, 0.75,
        -- export/download 엔드포인트 집중 공격
        countIf(request_uri LIKE '%export%' OR request_uri LIKE '%download%' OR request_uri LIKE '%report%') > 20, 0.6,
        0.1
    ) as edos_score

FROM http_packets
WHERE timestamp >= now() - INTERVAL 5 MINUTE
GROUP BY window_start, window_end, source_ip_hash, participant_id
HAVING count() >= 5;  -- 최소 5회 이상 요청만 집계


-- ----------------------------------------------------------------------------
-- 2. 자동 트리아지 MV (5분마다 갱신)
-- ----------------------------------------------------------------------------
-- 버그 리포트별 자동 분류 및 우선순위 판정

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_auto_triage
REFRESH EVERY 5 MINUTE
TO triage_results
AS
SELECT 
    report_id,
    
    min(timestamp) as first_seen,
    max(timestamp) as last_seen,
    count() as total_requests,
    
    -- ========================================
    -- 트리아지 상태 판정
    -- ========================================
    multiIf(
        -- 서버 크래시 발생
        countIf(response_status >= 500) > 0, 'CRASH_DETECTED',
        -- 에러 메시지 다수 발생 → 재현 가능성 높음
        countIf(
            response_body LIKE '%error%' 
            OR response_body LIKE '%exception%'
            OR response_body LIKE '%stack trace%'
        ) >= 3, 'LIKELY_REPRODUCIBLE',
        -- 인증 우회 시도 성공 가능성
        countIf(response_status = 200) > 0 
            AND countIf(request_uri LIKE '%admin%' OR request_uri LIKE '%internal%') > 0, 'AUTH_BYPASS_POSSIBLE',
        -- 모든 요청 성공 → 수동 검토 필요
        countIf(response_status = 200) = count(), 'NEEDS_MANUAL_REVIEW',
        -- 그 외
        'INCONCLUSIVE'
    ) as triage_status,
    
    -- ========================================
    -- 심각도 추정
    -- ========================================
    multiIf(
        -- 민감정보 노출 → Critical
        countIf(
            response_body LIKE '%password%' 
            OR response_body LIKE '%token%'
            OR response_body LIKE '%api_key%'
            OR response_body LIKE '%secret%'
        ) > 0, 'CRITICAL',
        -- 서버 크래시 → High
        countIf(response_status >= 500) > 0, 'HIGH',
        -- 인증 에러 다수 (권한 상승 시도) → Medium-High
        countIf(response_status IN (401, 403)) > 5, 'MEDIUM_HIGH',
        -- 그 외
        'LOW'
    ) as estimated_severity,
    
    -- 상세 메트릭
    countIf(response_status >= 500) as crash_count,
    countIf(response_status IN (401, 403)) as auth_error_count,
    countIf(response_status >= 200 AND response_status < 300) as success_count,
    
    -- PII 노출 여부
    if(countIf(
        match(response_body, 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+')
        OR match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}')
    ) > 0, 1, 0) as has_pii_exposure,
    
    groupUniqArrayIf(
        multiIf(
            match(response_body, 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+'), 'JWT',
            match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}'), 'EMAIL',
            ''
        ),
        match(response_body, 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+')
        OR match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}')
    ) as exposed_pii_types,
    
    now() as updated_at

FROM http_packets
WHERE report_id != '' AND report_id IS NOT NULL
GROUP BY report_id;


-- ----------------------------------------------------------------------------
-- 3. 차단 대상 자동 추가 MV (1분마다 갱신)
-- ----------------------------------------------------------------------------
-- 위협 점수 임계값 초과 시 자동으로 차단 목록에 추가

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_auto_block
REFRESH EVERY 1 MINUTE
TO block_list
AS
SELECT 
    source_ip_hash,
    participant_id,
    
    now() as blocked_at,
    now() + INTERVAL 1 HOUR as expires_at,  -- 기본 1시간 차단
    
    -- 차단 사유 생성
    concat(
        'Auto-blocked: ',
        arrayStringConcat(
            arrayFilter(x -> x != '',
                [
                    if(max(bruteforce_score) > 0.7, concat('Bruteforce(', toString(round(max(bruteforce_score), 2)), ')'), ''),
                    if(max(scanner_score) > 0.7, concat('Scanner(', toString(round(max(scanner_score), 2)), ')'), ''),
                    if(max(enumeration_score) > 0.7, concat('Enum(', toString(round(max(enumeration_score), 2)), ')'), ''),
                    if(max(edos_score) > 0.7, concat('EDoS(', toString(round(max(edos_score), 2)), ')'), '')
                ]
            ), ', '
        )
    ) as block_reason,
    
    greatest(
        max(bruteforce_score), 
        max(scanner_score), 
        max(enumeration_score), 
        max(edos_score)
    ) as threat_score,
    
    arrayFilter(x -> x != '',
        [
            if(max(bruteforce_score) > 0.7, 'BRUTEFORCE', ''),
            if(max(scanner_score) > 0.7, 'SCANNER', ''),
            if(max(enumeration_score) > 0.7, 'ENUMERATION', ''),
            if(max(edos_score) > 0.7, 'EDOS', '')
        ]
    ) as threat_types,
    
    1 as is_active,
    'SYSTEM' as created_by,
    '' as notes

FROM attack_detection_agg
WHERE window_start >= now() - INTERVAL 10 MINUTE
GROUP BY source_ip_hash, participant_id
HAVING greatest(
    max(bruteforce_score), 
    max(scanner_score), 
    max(enumeration_score), 
    max(edos_score)
) > 0.7;


-- ----------------------------------------------------------------------------
-- 4. 일간 요약 리포트 MV (1시간마다 갱신)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS daily_summary
(
    report_date Date,
    
    -- 트래픽 통계
    total_packets UInt64,
    unique_sessions UInt32,
    unique_participants UInt32,
    unique_reports UInt32,
    
    -- 응답 상태 분포
    status_2xx UInt64,
    status_4xx UInt64,
    status_5xx UInt64,
    
    -- 공격 탐지 통계
    blocked_ips UInt32,
    bruteforce_detections UInt32,
    scanner_detections UInt32,
    enumeration_detections UInt32,
    edos_detections UInt32,
    
    -- PII 노출 통계
    pii_exposures UInt64,
    critical_pii_exposures UInt64,
    
    -- 트리아지 통계
    reports_crash_detected UInt32,
    reports_likely_reproducible UInt32,
    reports_needs_review UInt32,
    
    updated_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (report_date);

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_summary
REFRESH EVERY 1 HOUR
TO daily_summary
AS
SELECT 
    toDate(timestamp) as report_date,
    
    count() as total_packets,
    uniq(session_id) as unique_sessions,
    uniq(participant_id) as unique_participants,
    uniqIf(report_id, report_id != '') as unique_reports,
    
    countIf(response_status >= 200 AND response_status < 300) as status_2xx,
    countIf(response_status >= 400 AND response_status < 500) as status_4xx,
    countIf(response_status >= 500) as status_5xx,
    
    0 as blocked_ips,  -- 별도 조인 필요
    0 as bruteforce_detections,
    0 as scanner_detections,
    0 as enumeration_detections,
    0 as edos_detections,
    
    countIf(
        match(response_body, 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+')
        OR match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}')
    ) as pii_exposures,
    
    countIf(
        match(response_body, 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+')
        OR match(response_body, '"[Aa]pi[_-]?[Kk]ey"')
    ) as critical_pii_exposures,
    
    0 as reports_crash_detected,
    0 as reports_likely_reproducible,
    0 as reports_needs_review,
    
    now() as updated_at

FROM http_packets
WHERE timestamp >= today() - INTERVAL 7 DAY
GROUP BY report_date;
