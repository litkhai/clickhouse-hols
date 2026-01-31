-- ============================================================================
-- Bug Bounty Packet Analysis Platform - Step 2: Core Tables
-- 버그바운티 패킷 분석 플랫폼 - Step 2: 핵심 테이블 생성
-- ============================================================================
-- Created: 2026-01-31
-- 작성일: 2026-01-31
-- Purpose: Create core tables for packet data storage and analysis
-- 목적: 패킷 데이터 저장 및 분석을 위한 핵심 테이블 생성
-- Expected time: ~2-3 seconds
-- 예상 시간: ~2-3초
-- ============================================================================

USE bug_bounty;

-- ============================================================================
-- 2.1 Raw HTTP Packets Table
-- 2.1 원본 HTTP 패킷 테이블
-- ============================================================================
-- Features: Store all HTTP request/response packets in original form
-- 특징: 모든 HTTP 요청/응답 패킷을 원본 그대로 저장
-- Partitioning: Monthly / TTL: 90 days
-- 파티셔닝: 월별 / TTL: 90일
-- ============================================================================

CREATE TABLE IF NOT EXISTS http_packets
(
    -- Basic identification / 기본 식별 정보
    packet_id UUID DEFAULT generateUUIDv4(),           -- Packet identifier / 패킷 식별자
    session_id String,                                 -- Session identifier (group of consecutive requests) / 세션 식별자 (연속된 요청 그룹)
    report_id String,                                  -- Bug bounty report ID (BUG-YYYY-NNNN) / 버그바운티 리포트 ID
    participant_id String,                             -- Participant ID (before hashing) / 참여자 ID (해시 처리 전)

    -- Time information / 시간 정보
    timestamp DateTime64(3),                           -- Packet capture time (millisecond precision) / 패킷 캡처 시각 (밀리초 정밀도)

    -- Request information / 요청 정보
    request_method LowCardinality(String),             -- HTTP method (GET, POST, etc.) / HTTP 메서드
    request_uri String,                                -- Request URI (including query string) / 요청 URI (쿼리스트링 포함)
    request_headers Map(String, String),               -- Request headers / 요청 헤더
    request_body String,                               -- Request body (JSON, Form, etc.) / 요청 바디

    -- Response information / 응답 정보
    response_status UInt16,                            -- HTTP status code / HTTP 상태 코드
    response_headers Map(String, String),              -- Response headers / 응답 헤더
    response_body String,                              -- Response body / 응답 바디
    response_time_ms UInt32,                           -- Response time in milliseconds / 응답 시간 (밀리초)

    -- Network information / 네트워크 정보
    source_ip String,                                  -- Source IP (anonymization target) / 소스 IP (비식별화 대상)
    dest_ip String,                                    -- Destination IP / 목적지 IP
    source_port UInt16 DEFAULT 0,                      -- Source port / 소스 포트
    dest_port UInt16 DEFAULT 0,                        -- Destination port / 목적지 포트

    -- Metadata / 메타데이터
    content_length UInt64 DEFAULT 0,                   -- Content length / 컨텐츠 길이
    user_agent String DEFAULT '',                      -- User-Agent header / User-Agent 헤더
    referer String DEFAULT '',                         -- Referer header / Referer 헤더

    -- Analysis flags (updated later) / 분석용 플래그 (나중에 업데이트)
    is_suspicious UInt8 DEFAULT 0,                     -- Suspicious traffic flag / 의심 트래픽 여부
    attack_type LowCardinality(String) DEFAULT '',     -- Detected attack type / 탐지된 공격 유형

    -- Partitioning/Indexing / 파티셔닝/인덱싱용
    event_date Date DEFAULT toDate(timestamp)          -- Event date / 이벤트 날짜
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (session_id, timestamp, packet_id)
TTL event_date + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Add secondary indexes / 보조 인덱스 추가
ALTER TABLE http_packets ADD INDEX idx_report_id (report_id) TYPE bloom_filter GRANULARITY 4;
ALTER TABLE http_packets ADD INDEX idx_source_ip (source_ip) TYPE bloom_filter GRANULARITY 4;
ALTER TABLE http_packets ADD INDEX idx_response_status (response_status) TYPE minmax GRANULARITY 4;


-- ============================================================================
-- 2.2 Anonymized Packets Table
-- 2.2 비식별화된 패킷 테이블
-- ============================================================================
-- Features: Automatically anonymized data via MV, suitable for AI training
-- 특징: MV를 통해 자동으로 비식별화된 데이터 저장, AI 학습 데이터로 활용 가능
-- Partitioning: Monthly / TTL: 365 days
-- 파티셔닝: 월별 / TTL: 365일
-- ============================================================================

CREATE TABLE IF NOT EXISTS http_packets_anonymized
(
    packet_id UUID,                                    -- Packet identifier / 패킷 식별자
    session_id String,                                 -- Session identifier / 세션 식별자
    report_id String,                                  -- Report ID / 리포트 ID
    participant_id_hash String,                        -- SHA256 hashed participant ID / SHA256 해시된 참여자 ID

    timestamp DateTime64(3),                           -- Timestamp / 타임스탬프

    request_method LowCardinality(String),             -- HTTP method / HTTP 메서드
    request_uri_sanitized String,                      -- URI with PII masked / 민감정보 마스킹된 URI
    request_body_sanitized String,                     -- Request body with PII masked / 민감정보 마스킹된 요청 바디

    response_status UInt16,                            -- HTTP status code / HTTP 상태 코드
    response_body_sanitized String,                    -- Response body with PII masked / 민감정보 마스킹된 응답 바디
    response_time_ms UInt32,                           -- Response time / 응답 시간

    source_ip_hash String,                             -- IP hash value / IP 해시값

    -- Detected PII metadata (preserved after masking) / 탐지된 민감정보 타입 (마스킹 후 메타데이터로 보존)
    detected_pii_types Array(String),                  -- List of detected PII types / 탐지된 PII 유형 목록
    pii_count UInt8 DEFAULT 0,                         -- Number of detected PII / 탐지된 PII 개수

    event_date Date                                    -- Event date / 이벤트 날짜
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (session_id, timestamp, packet_id)
TTL event_date + INTERVAL 365 DAY
SETTINGS index_granularity = 8192;


-- ============================================================================
-- 2.3 Attack Detection Aggregates Table
-- 2.3 공격 탐지 집계 테이블
-- ============================================================================
-- Features: Aggregate attack patterns in 1-minute windows
-- 특징: 1분 단위 윈도우로 공격 패턴 집계
-- Engine: SummingMergeTree for efficient aggregation
-- 엔진: SummingMergeTree로 효율적인 집계
-- ============================================================================

CREATE TABLE IF NOT EXISTS attack_detection_agg
(
    window_start DateTime,                             -- Aggregation window start time / 집계 윈도우 시작 시각
    window_end DateTime,                               -- Aggregation window end time / 집계 윈도우 종료 시각
    source_ip_hash String,                             -- Source IP hash / 소스 IP 해시
    participant_id String,                             -- Participant ID / 참여자 ID

    -- Aggregation metrics / 집계 메트릭
    request_count UInt64,                              -- Number of requests / 요청 수
    unique_endpoints UInt32,                           -- Number of unique endpoints / 고유 엔드포인트 수
    error_count UInt32,                                -- Number of error responses / 에러 응답 수
    total_response_time UInt64,                        -- Total response time (for average calculation) / 총 응답 시간 (평균 계산용)
    total_content_length UInt64,                       -- Total content length / 총 컨텐츠 길이

    -- Detection scores (0.0 ~ 1.0) / 탐지 점수
    bruteforce_score Float32,                          -- Brute force attack score / Bruteforce 공격 점수
    scanner_score Float32,                             -- Scanner attack score / Scanner 공격 점수
    enumeration_score Float32,                         -- Enumeration attack score / Enumeration 공격 점수
    edos_score Float32,                                -- EDoS attack score / EDoS 공격 점수

    -- Verdict results / 판정 결과
    is_blocked UInt8 DEFAULT 0,                        -- Block status / 차단 여부
    block_reason String DEFAULT ''                     -- Block reason / 차단 사유
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMMDD(window_start)
ORDER BY (window_start, source_ip_hash, participant_id)
TTL window_start + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;


-- ============================================================================
-- 2.4 Auto Triage Results Table
-- 2.4 자동 트리아지 결과 테이블
-- ============================================================================
-- Features: Store automatic classification results per report
-- 특징: 리포트별 자동 분류 결과 저장
-- Engine: ReplacingMergeTree for deduplication
-- 엔진: ReplacingMergeTree로 중복 제거
-- ============================================================================

CREATE TABLE IF NOT EXISTS triage_results
(
    report_id String,                                  -- Bug bounty report ID / 버그바운티 리포트 ID

    first_seen DateTime64(3),                          -- First request time / 최초 요청 시각
    last_seen DateTime64(3),                           -- Last request time / 최종 요청 시각
    total_requests UInt64,                             -- Total number of requests / 총 요청 수

    -- Triage results / 트리아지 결과
    triage_status LowCardinality(String),              -- Triage status / 트리아지 상태
    estimated_severity LowCardinality(String),         -- Estimated severity / 추정 심각도

    -- Detailed metrics / 상세 메트릭
    crash_count UInt32 DEFAULT 0,                      -- Crash (5xx) response count / 크래시(5xx) 응답 수
    auth_error_count UInt32 DEFAULT 0,                 -- Auth error (401/403) count / 인증 에러(401/403) 수
    success_count UInt32 DEFAULT 0,                    -- Success (2xx) response count / 성공(2xx) 응답 수

    -- PII exposure / 민감정보 노출 여부
    has_pii_exposure UInt8 DEFAULT 0,                  -- PII exposure flag / PII 노출 여부
    exposed_pii_types Array(String) DEFAULT [],        -- Types of exposed PII / 노출된 PII 유형

    updated_at DateTime DEFAULT now()                  -- Last update time / 마지막 업데이트 시각
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (report_id)
SETTINGS index_granularity = 8192;


-- ============================================================================
-- 2.5 Block List Table
-- 2.5 차단 목록 테이블
-- ============================================================================
-- Features: Real-time block target management
-- 특징: 실시간 차단 대상 관리
-- Engine: ReplacingMergeTree for latest status
-- 엔진: ReplacingMergeTree로 최신 상태 유지
-- ============================================================================

CREATE TABLE IF NOT EXISTS block_list
(
    source_ip_hash String,                             -- Blocked IP hash / 차단 대상 IP 해시
    participant_id String,                             -- Participant ID / 참여자 ID

    blocked_at DateTime DEFAULT now(),                 -- Block time / 차단 시각
    expires_at DateTime,                               -- Block expiration time / 차단 만료 시각

    block_reason String,                               -- Block reason / 차단 사유
    threat_score Float32,                              -- Threat score / 위협 점수
    threat_types Array(String),                        -- Detected threat types / 탐지된 위협 유형

    is_active UInt8 DEFAULT 1,                         -- Active block status / 활성 차단 여부

    -- Management fields / 관리용
    created_by String DEFAULT 'SYSTEM',                -- Creator / 생성자
    notes String DEFAULT ''                            -- Administrator notes / 관리자 메모
)
ENGINE = ReplacingMergeTree(blocked_at)
ORDER BY (source_ip_hash, participant_id)
SETTINGS index_granularity = 8192;


-- ============================================================================
-- 2.6 PII Exposure Log Table
-- 2.6 PII 노출 이력 테이블
-- ============================================================================
-- Features: Detailed logging of PII exposure events
-- 특징: 민감정보 노출 이벤트 상세 기록
-- Partitioning: Monthly / TTL: 180 days
-- 파티셔닝: 월별 / TTL: 180일
-- ============================================================================

CREATE TABLE IF NOT EXISTS pii_exposure_log
(
    exposure_id UUID DEFAULT generateUUIDv4(),         -- Exposure event ID / 노출 이벤트 ID
    packet_id UUID,                                    -- Original packet ID / 원본 패킷 ID

    timestamp DateTime64(3),                           -- Timestamp / 타임스탬프
    session_id String,                                 -- Session ID / 세션 ID
    report_id String,                                  -- Report ID / 리포트 ID

    pii_type LowCardinality(String),                   -- PII type (JWT, API_KEY, EMAIL, etc.) / PII 유형
    pii_location LowCardinality(String),               -- Detection location (REQUEST_URI, REQUEST_BODY, RESPONSE_BODY) / 발견 위치

    -- Context (stored in masked state) / 컨텍스트 (마스킹된 상태로 저장)
    context_snippet String,                            -- Surrounding context (masked) / 주변 컨텍스트 (마스킹됨)

    -- Severity / 심각도
    severity LowCardinality(String),                   -- Severity (CRITICAL, HIGH, MEDIUM, LOW) / 심각도

    event_date Date DEFAULT toDate(timestamp)          -- Event date / 이벤트 날짜
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, pii_type, timestamp)
TTL event_date + INTERVAL 180 DAY
SETTINGS index_granularity = 8192;


-- ============================================================================
-- Verify Schema Creation
-- 스키마 생성 확인
-- ============================================================================

SELECT
    name AS table_name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = 'bug_bounty'
ORDER BY name;
