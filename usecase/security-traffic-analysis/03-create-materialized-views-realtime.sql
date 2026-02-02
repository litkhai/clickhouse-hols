-- ============================================================================
-- Bug Bounty Packet Analysis Platform - Step 3: Real-time Materialized Views
-- 버그바운티 패킷 분석 플랫폼 - Step 3: 실시간 Materialized Views 생성
-- ============================================================================
-- Created: 2026-01-31
-- 작성일: 2026-01-31
-- Purpose: Create real-time data processing pipelines with materialized views
-- 목적: 자동화된 실시간 데이터 처리 파이프라인 구축
-- Expected time: ~2-3 seconds
-- 예상 시간: ~2-3초
-- ============================================================================

USE bug_bounty;

-- ============================================================================
-- 3.1 Anonymization Pipeline MV (Real-time)
-- 3.1 비식별화 파이프라인 MV (실시간)
-- ============================================================================
-- Features: Automatically anonymize data as it arrives
-- 특징: 원본 데이터가 들어오면 자동으로 비식별화하여 저장
-- Detection: Uses regex patterns to detect and mask various PII types
-- 탐지 방식: 정규식을 사용하여 다양한 민감정보 패턴 탐지 및 마스킹
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_anonymize_packets
TO http_packets_anonymized
AS
SELECT
    packet_id,
    session_id,
    report_id,
    hex(SHA256(participant_id)) as participant_id_hash,        -- SHA256 hash of participant ID / 참여자 ID SHA256 해시

    timestamp,

    request_method,

    -- URI anonymization: Mask API Key, Token, Password parameters
    -- URI 비식별화: API Key, Token, Password 파라미터 마스킹
    replaceRegexpAll(
        replaceRegexpAll(
            replaceRegexpAll(
                replaceRegexpAll(request_uri,
                    '[Aa]pi[_-]?[Kk]ey=[^&\\s]+', 'api_key=[REDACTED]'),
                '[Tt]oken=[^&\\s]+', 'token=[REDACTED]'),
            '[Pp]assword=[^&\\s]+', 'password=[REDACTED]'),
        '[Ss]ecret=[^&\\s]+', 'secret=[REDACTED]'
    ) as request_uri_sanitized,

    -- Request Body anonymization / Request Body 비식별화
    replaceRegexpAll(
        replaceRegexpAll(
            replaceRegexpAll(
                replaceRegexpAll(
                    replaceRegexpAll(request_body,
                        -- Password field / password 필드
                        '"[Pp]assword"\\s*:\\s*"[^"]+"', '"password":"[REDACTED]"'),
                    -- API key field / api_key 필드
                    '"[Aa]pi[_-]?[Kk]ey"\\s*:\\s*"[^"]+"', '"api_key":"[REDACTED]"'),
                -- Token field / token 필드
                '"[Tt]oken"\\s*:\\s*"[^"]+"', '"token":"[REDACTED]"'),
            -- Secret field / secret 필드
            '"[Ss]ecret"\\s*:\\s*"[^"]+"', '"secret":"[REDACTED]"'),
        -- Email pattern / 이메일 패턴
        '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}', '[EMAIL_REDACTED]'
    ) as request_body_sanitized,

    response_status,

    -- Response Body anonymization (most critical - handles various patterns)
    -- Response Body 비식별화 (가장 중요 - 다양한 패턴 처리)
    replaceRegexpAll(
        replaceRegexpAll(
            replaceRegexpAll(
                replaceRegexpAll(
                    replaceRegexpAll(
                        replaceRegexpAll(
                            replaceRegexpAll(
                                replaceRegexpAll(response_body,
                                    -- JWT token pattern (Header.Payload.Signature) / JWT 토큰 패턴
                                    'eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}', '[JWT_REDACTED]'),
                                -- Bearer token / Bearer 토큰
                                '[Bb]earer\\s+[A-Za-z0-9_-]{20,}', 'Bearer [TOKEN_REDACTED]'),
                            -- API Key pattern (JSON field) / API Key 패턴
                            '"[Aa]pi[_-]?[Kk]ey"\\s*:\\s*"[^"]+"', '"api_key":"[REDACTED]"'),
                        -- Access Token pattern / Access Token 패턴
                        '"[Aa]ccess[_-]?[Tt]oken"\\s*:\\s*"[^"]+"', '"access_token":"[REDACTED]"'),
                    -- Refresh Token pattern / Refresh Token 패턴
                    '"[Rr]efresh[_-]?[Tt]oken"\\s*:\\s*"[^"]+"', '"refresh_token":"[REDACTED]"'),
                -- Email pattern / 이메일 패턴
                '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}', '[EMAIL_REDACTED]'),
            -- Korean phone number pattern / 한국 전화번호 패턴
            '01[0-9]-?[0-9]{3,4}-?[0-9]{4}', '[PHONE_REDACTED]'),
        -- Credit card number pattern / 신용카드 번호 패턴
        '\\b[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\\b', '[CARD_REDACTED]'
    ) as response_body_sanitized,

    response_time_ms,

    -- IP hash (irreversible) / IP 해시 (복원 불가능하도록)
    hex(SHA256(concat(source_ip, 'salt_for_ip_hash_2024'))) as source_ip_hash,

    -- Record detected PII types (preserve metadata about what was found)
    -- 탐지된 PII 타입 기록 (어떤 종류의 민감정보가 있었는지 메타데이터로 보존)
    arrayFilter(x -> x != '',
        [
            if(match(response_body, 'eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}'), 'JWT', ''),
            if(match(response_body, '"[Aa]pi[_-]?[Kk]ey"\\s*:\\s*"[^"]+"'), 'API_KEY', ''),
            if(match(response_body, '"[Aa]ccess[_-]?[Tt]oken"\\s*:\\s*"[^"]+"'), 'ACCESS_TOKEN', ''),
            if(match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}'), 'EMAIL', ''),
            if(match(response_body, '01[0-9]-?[0-9]{3,4}-?[0-9]{4}'), 'PHONE_KR', ''),
            if(match(response_body, '\\b[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\\b'), 'CREDIT_CARD', ''),
            if(match(request_body, '"[Pp]assword"\\s*:\\s*"[^"]+"'), 'PASSWORD_IN_REQUEST', '')
        ]
    ) as detected_pii_types,

    -- Count of detected PII / 탐지된 PII 개수
    length(arrayFilter(x -> x != '',
        [
            if(match(response_body, 'eyJ[A-Za-z0-9_-]{10,}'), 'x', ''),
            if(match(response_body, '"[Aa]pi[_-]?[Kk]ey"'), 'x', ''),
            if(match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}'), 'x', ''),
            if(match(response_body, '01[0-9]-?[0-9]{3,4}-?[0-9]{4}'), 'x', ''),
            if(match(response_body, '\\b[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\\b'), 'x', '')
        ]
    )) as pii_count,

    event_date

FROM http_packets;


-- ============================================================================
-- 3.2 PII Exposure Log MV (Real-time)
-- 3.2 PII 노출 이력 MV (실시간)
-- ============================================================================
-- Features: Record detailed logs only when PII is detected
-- 특징: 민감정보가 탐지된 경우에만 상세 이력 기록
-- Purpose: Track and audit all PII exposure incidents
-- 목적: 모든 PII 노출 사건을 추적하고 감사
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_pii_exposure_log
TO pii_exposure_log
AS
SELECT
    generateUUIDv4() as exposure_id,                   -- Unique exposure event ID / 고유 노출 이벤트 ID
    packet_id,
    timestamp,
    session_id,
    report_id,

    -- Use arrayJoin to create one row per PII type detected
    -- arrayJoin을 사용하여 탐지된 PII 타입별로 한 행씩 생성
    arrayJoin(
        arrayFilter(x -> x != '',
            [
                if(match(response_body, 'eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}'), 'JWT', ''),
                if(match(response_body, '"[Aa]pi[_-]?[Kk]ey"\\s*:\\s*"[^"]+"'), 'API_KEY', ''),
                if(match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}'), 'EMAIL', ''),
                if(match(response_body, '01[0-9]-?[0-9]{3,4}-?[0-9]{4}'), 'PHONE_KR', ''),
                if(match(response_body, '\\b[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\\b'), 'CREDIT_CARD', '')
            ]
        )
    ) as pii_type,

    'RESPONSE_BODY' as pii_location,                   -- Location where PII was found / PII 발견 위치

    -- Context snippet (in masked state) / 컨텍스트 스니펫 (마스킹된 상태)
    substring(
        replaceRegexpAll(response_body, 'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+', '[JWT]'),
        1, 200
    ) as context_snippet,

    -- Severity determination / 심각도 판정
    multiIf(
        match(response_body, 'eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}'), 'CRITICAL',
        match(response_body, '"[Aa]pi[_-]?[Kk]ey"'), 'CRITICAL',
        match(response_body, '\\b[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\\b'), 'CRITICAL',
        match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}'), 'HIGH',
        match(response_body, '01[0-9]-?[0-9]{3,4}-?[0-9]{4}'), 'HIGH',
        'MEDIUM'
    ) as severity,

    event_date

FROM http_packets
WHERE
    -- Only process packets with PII detected / PII가 탐지된 패킷만 처리
    match(response_body, 'eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}')
    OR match(response_body, '"[Aa]pi[_-]?[Kk]ey"\\s*:\\s*"[^"]+"')
    OR match(response_body, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}')
    OR match(response_body, '01[0-9]-?[0-9]{3,4}-?[0-9]{4}')
    OR match(response_body, '\\b[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\\b');


-- ============================================================================
-- Verify Materialized Views Creation
-- Materialized Views 생성 확인
-- ============================================================================

SELECT
    name AS view_name,
    engine,
    total_rows
FROM system.tables
WHERE database = 'bug_bounty' AND name LIKE 'mv_%'
ORDER BY name;
