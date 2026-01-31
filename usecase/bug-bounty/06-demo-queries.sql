-- ============================================================================
-- Bug Bounty Packet Analysis Platform - Step 6: Demo Queries
-- 버그바운티 패킷 분석 플랫폼 - Step 6: 데모 쿼리
-- ============================================================================
-- Created: 2026-01-31
-- 작성일: 2026-01-31
-- Purpose: Collection of analysis queries for demonstration
-- 목적: 데모 시연을 위한 분석 쿼리 모음
-- Expected time: ~5-30 seconds per query (varies by complexity)
-- 예상 시간: 쿼리당 ~5-30초 (복잡도에 따라 다름)
-- ============================================================================

USE bug_bounty;

-- ############################################################################
-- PART 1: 취약점 재현 자동화 + 회귀 검증
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 1.1 특정 리포트의 요청 시퀀스 추출
-- ----------------------------------------------------------------------------
-- 버그 리포트 ID로 해당 취약점 테스트 시퀀스를 시간순으로 조회

SELECT 
    timestamp,
    request_method,
    request_uri,
    substring(request_body, 1, 100) as request_body_preview,
    response_status,
    substring(response_body, 1, 200) as response_body_preview,
    response_time_ms
FROM http_packets
WHERE report_id = 'BUG-2024-1234'
ORDER BY timestamp
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 1.2 재현 성공 여부 자동 판정
-- ----------------------------------------------------------------------------
-- 응답 패턴 분석을 통한 취약점 재현 확인

SELECT 
    report_id,
    count() as total_requests,
    
    -- 취약점 재현 지표
    countIf(response_status >= 500) as server_errors,
    countIf(response_body LIKE '%SQL syntax error%' 
         OR response_body LIKE '%exception%'
         OR response_body LIKE '%stack trace%') as error_patterns_found,
    countIf(response_body LIKE '%password%' 
         OR response_body LIKE '%token%'
         OR response_body LIKE '%secret%') as sensitive_data_exposed,
    
    -- 판정 결과
    multiIf(
        countIf(response_body LIKE '%password%' OR response_body LIKE '%secret%') > 0, '🔴 CRITICAL - 민감정보 노출',
        countIf(response_status >= 500) > 0, '🟠 HIGH - 서버 에러 유발',
        countIf(response_body LIKE '%error%') >= 2, '🟡 MEDIUM - 재현 가능성 높음',
        '🟢 LOW - 추가 검토 필요'
    ) as verdict

FROM http_packets
WHERE report_id = 'BUG-2024-1234'
GROUP BY report_id
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 1.3 패치 전후 비교 (회귀 검증)
-- ----------------------------------------------------------------------------
-- 동일 공격 시퀀스의 패치 전/후 결과 비교

SELECT 
    multiIf(
        timestamp < now() - INTERVAL 36 HOUR, '1️⃣ BEFORE_PATCH',
        '2️⃣ AFTER_PATCH'
    ) as phase,
    
    count() as total_requests,
    countIf(response_status >= 500) as server_errors,
    countIf(response_status >= 400 AND response_status < 500) as client_errors,
    countIf(response_status >= 200 AND response_status < 300) as success_responses,
    
    -- 취약점 트리거 여부
    countIf(response_body LIKE '%SQL syntax error%' 
         OR response_body LIKE '%password_hash%') as vulnerability_triggered,
    
    -- 회귀 여부 판정
    if(countIf(response_body LIKE '%SQL syntax error%' OR response_body LIKE '%password_hash%') > 0,
       '❌ 취약점 존재',
       '✅ 취약점 수정됨'
    ) as regression_status

FROM http_packets
WHERE report_id = 'BUG-2024-1234'
GROUP BY phase
ORDER BY phase
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 1.4 자동 트리아지 결과 대시보드
-- ----------------------------------------------------------------------------
-- 전체 버그 리포트의 자동 분류 현황

SELECT 
    triage_status,
    estimated_severity,
    count() as report_count,
    round(avg(total_requests), 1) as avg_requests,
    sum(crash_count) as total_crashes,
    sum(if(has_pii_exposure = 1, 1, 0)) as pii_exposure_reports

FROM triage_results
GROUP BY triage_status, estimated_severity
ORDER BY 
    multiIf(
        estimated_severity = 'CRITICAL', 1,
        estimated_severity = 'HIGH', 2,
        estimated_severity = 'MEDIUM_HIGH', 3,
        4
    ),
    triage_status
FORMAT PrettyCompactMonoBlock;


-- ############################################################################
-- PART 2: 자동화 공격 탐지·차단
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 2.1 실시간 위협 대시보드
-- ----------------------------------------------------------------------------
-- 최근 10분간 탐지된 위협 요약

SELECT 
    source_ip_hash,
    participant_id,
    
    sum(request_count) as total_requests,
    round(avg(unique_endpoints), 1) as avg_unique_endpoints,
    
    -- 위협 점수 (최대값)
    round(max(bruteforce_score), 2) as bruteforce_risk,
    round(max(scanner_score), 2) as scanner_risk,
    round(max(enumeration_score), 2) as enum_risk,
    round(max(edos_score), 2) as edos_risk,
    
    -- 종합 위협 점수
    round(greatest(
        max(bruteforce_score),
        max(scanner_score),
        max(enumeration_score),
        max(edos_score)
    ), 2) as max_threat_score,
    
    -- 위협 유형 태그
    arrayStringConcat(
        arrayFilter(x -> x != '', [
            if(max(bruteforce_score) > 0.5, '🔐Bruteforce', ''),
            if(max(scanner_score) > 0.5, '🔍Scanner', ''),
            if(max(enumeration_score) > 0.5, '📋Enum', ''),
            if(max(edos_score) > 0.5, '💥EDoS', '')
        ]), ' '
    ) as threat_tags

FROM attack_detection_agg
WHERE window_start >= now() - INTERVAL 1 HOUR
GROUP BY source_ip_hash, participant_id
HAVING max_threat_score > 0.3
ORDER BY max_threat_score DESC
LIMIT 20
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 2.2 차단 대상 IP 목록 (임계값 0.7 초과)
-- ----------------------------------------------------------------------------

SELECT 
    source_ip_hash,
    participant_id,
    
    -- 요청 통계
    sum(request_count) as total_requests,
    count() as detection_windows,
    
    -- 위협 점수
    round(max(bruteforce_score), 2) as bruteforce,
    round(max(scanner_score), 2) as scanner,
    round(max(enumeration_score), 2) as enumeration,
    round(max(edos_score), 2) as edos,
    
    -- 주요 위협
    arrayStringConcat(
        arrayFilter(x -> x != '', [
            if(max(bruteforce_score) > 0.7, 'BRUTEFORCE', ''),
            if(max(scanner_score) > 0.7, 'SCANNER', ''),
            if(max(enumeration_score) > 0.7, 'ENUMERATION', ''),
            if(max(edos_score) > 0.7, 'EDOS', '')
        ]), ', '
    ) as primary_threats,
    
    '🚫 BLOCK RECOMMENDED' as action

FROM attack_detection_agg
WHERE window_start >= now() - INTERVAL 1 HOUR
GROUP BY source_ip_hash, participant_id
HAVING greatest(
    max(bruteforce_score),
    max(scanner_score),
    max(enumeration_score),
    max(edos_score)
) > 0.7
ORDER BY greatest(
    max(bruteforce_score),
    max(scanner_score),
    max(enumeration_score),
    max(edos_score)
) DESC
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 2.3 Bruteforce 공격 상세 분석
-- ----------------------------------------------------------------------------

SELECT 
    toStartOfMinute(timestamp) as minute,
    source_ip,
    request_uri,
    count() as attempts,
    countIf(response_status = 401) as failed_auth,
    countIf(response_status = 200) as success_auth,
    
    if(countIf(response_status = 200) > 0 AND countIf(response_status = 401) > 10,
       '⚠️ 크리덴셜 스터핑 성공 의심',
       if(countIf(response_status = 401) > 50, '🔴 브루트포스 진행중', '🟢 정상')
    ) as status

FROM http_packets
WHERE request_uri LIKE '%login%' OR request_uri LIKE '%auth%'
  AND timestamp >= now() - INTERVAL 1 HOUR
GROUP BY minute, source_ip, request_uri
HAVING count() > 5
ORDER BY minute DESC, attempts DESC
LIMIT 30
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 2.4 Scanner/Enumeration 패턴 분석
-- ----------------------------------------------------------------------------

SELECT 
    source_ip,
    participant_id,
    
    -- 엔드포인트 탐색 패턴
    uniq(request_uri) as unique_endpoints,
    count() as total_requests,
    
    -- 응답 분포
    countIf(response_status = 200) as found_200,
    countIf(response_status = 403) as forbidden_403,
    countIf(response_status = 404) as not_found_404,
    
    -- 민감 경로 접근 시도
    countIf(request_uri LIKE '%admin%') as admin_attempts,
    countIf(request_uri LIKE '%config%' OR request_uri LIKE '%.env%') as config_attempts,
    countIf(match(request_uri, '/api/users/[0-9]+')) as user_enum_attempts,
    
    -- 판정
    multiIf(
        countIf(request_uri LIKE '%admin%') > 5 AND countIf(response_status = 200) > 0, 
            '🔴 CRITICAL - 관리자 접근 성공',
        uniq(request_uri) > 30, 
            '🟠 HIGH - 광범위 스캐닝',
        countIf(match(request_uri, '/api/users/[0-9]+')) > 20, 
            '🟡 MEDIUM - ID 열거 시도',
        '🟢 LOW'
    ) as threat_level

FROM http_packets
WHERE timestamp >= now() - INTERVAL 1 HOUR
GROUP BY source_ip, participant_id
HAVING uniq(request_uri) > 10 OR countIf(request_uri LIKE '%admin%') > 3
ORDER BY unique_endpoints DESC
LIMIT 20
FORMAT PrettyCompactMonoBlock;


-- ############################################################################
-- PART 3: 민감정보 노출 비식별화
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 3.1 원본 vs 비식별화 데이터 비교
-- ----------------------------------------------------------------------------

SELECT 
    '원본 데이터' as data_type,
    packet_id,
    participant_id as participant,
    source_ip,
    substring(response_body, 1, 150) as response_preview
FROM http_packets
WHERE session_id LIKE 'pii-session%'
LIMIT 3

UNION ALL

SELECT 
    '비식별화 데이터' as data_type,
    packet_id,
    substring(participant_id_hash, 1, 16) as participant,
    substring(source_ip_hash, 1, 16) as source_ip,
    substring(response_body_sanitized, 1, 150) as response_preview
FROM http_packets_anonymized
WHERE session_id LIKE 'pii-session%'
LIMIT 3

FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 3.2 민감정보 노출 통계 대시보드
-- ----------------------------------------------------------------------------

SELECT 
    toDate(timestamp) as date,
    pii_type,
    count() as exposure_count,
    uniq(session_id) as affected_sessions,
    uniq(report_id) as affected_reports,
    
    -- 심각도별 분류
    countIf(severity = 'CRITICAL') as critical_count,
    countIf(severity = 'HIGH') as high_count

FROM pii_exposure_log
WHERE event_date >= today() - INTERVAL 7 DAY
GROUP BY date, pii_type
ORDER BY date DESC, exposure_count DESC
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 3.3 심각한 PII 노출 케이스 (JWT + API Key 동시 노출)
-- ----------------------------------------------------------------------------

SELECT 
    session_id,
    report_id,
    timestamp,
    detected_pii_types,
    pii_count,
    
    -- 위험도 표시
    multiIf(
        has(detected_pii_types, 'JWT') AND has(detected_pii_types, 'API_KEY'), '🔴 CRITICAL',
        has(detected_pii_types, 'CREDIT_CARD'), '🔴 CRITICAL',
        has(detected_pii_types, 'JWT') OR has(detected_pii_types, 'API_KEY'), '🟠 HIGH',
        has(detected_pii_types, 'EMAIL') OR has(detected_pii_types, 'PHONE_KR'), '🟡 MEDIUM',
        '🟢 LOW'
    ) as risk_level

FROM http_packets_anonymized
WHERE length(detected_pii_types) > 0
ORDER BY 
    pii_count DESC,
    timestamp DESC
LIMIT 20
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 3.4 AI 학습용 비식별화 데이터셋 추출
-- ----------------------------------------------------------------------------
-- 민감정보가 마스킹된 깨끗한 데이터셋

SELECT 
    session_id,
    request_method,
    request_uri_sanitized as request_uri,
    response_status,
    response_body_sanitized as response_body,
    response_time_ms,
    
    -- 메타데이터 (학습에 활용)
    detected_pii_types as original_pii_types,  -- 어떤 PII가 있었는지는 보존
    pii_count

FROM http_packets_anonymized
WHERE event_date >= today() - INTERVAL 30 DAY
  AND response_status = 200
  AND length(response_body_sanitized) > 50
ORDER BY rand()
LIMIT 1000
FORMAT JSONEachRow;


-- ############################################################################
-- PART 4: 종합 대시보드 쿼리
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 4.1 일간 요약 리포트
-- ----------------------------------------------------------------------------

SELECT 
    '📊 일간 요약 리포트' as title,
    toString(today()) as report_date;

SELECT 
    '트래픽 현황' as category,
    count() as total_packets,
    uniq(session_id) as unique_sessions,
    uniq(participant_id) as unique_participants,
    uniqIf(report_id, report_id != '') as active_reports
FROM http_packets
WHERE event_date = today()
FORMAT PrettyCompactMonoBlock;

SELECT 
    '응답 상태 분포' as category,
    countIf(response_status >= 200 AND response_status < 300) as '2xx_success',
    countIf(response_status >= 400 AND response_status < 500) as '4xx_client_error',
    countIf(response_status >= 500) as '5xx_server_error'
FROM http_packets
WHERE event_date = today()
FORMAT PrettyCompactMonoBlock;

SELECT 
    '위협 탐지 현황' as category,
    countIf(bruteforce_score > 0.7) as bruteforce_alerts,
    countIf(scanner_score > 0.7) as scanner_alerts,
    countIf(enumeration_score > 0.7) as enum_alerts,
    countIf(edos_score > 0.7) as edos_alerts
FROM attack_detection_agg
WHERE toDate(window_start) = today()
FORMAT PrettyCompactMonoBlock;

SELECT 
    'PII 노출 현황' as category,
    count() as total_exposures,
    countIf(severity = 'CRITICAL') as critical,
    countIf(severity = 'HIGH') as high,
    uniq(pii_type) as pii_types_found
FROM pii_exposure_log
WHERE event_date = today()
FORMAT PrettyCompactMonoBlock;


-- ----------------------------------------------------------------------------
-- 4.2 현재 차단 목록
-- ----------------------------------------------------------------------------

SELECT 
    source_ip_hash,
    participant_id,
    blocked_at,
    expires_at,
    block_reason,
    round(threat_score, 2) as threat_score,
    threat_types,
    
    if(expires_at > now(), '🔴 ACTIVE', '⚪ EXPIRED') as status

FROM block_list
WHERE is_active = 1
ORDER BY blocked_at DESC
LIMIT 20
FORMAT PrettyCompactMonoBlock;
