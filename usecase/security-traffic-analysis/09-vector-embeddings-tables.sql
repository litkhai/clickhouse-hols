-- ============================================================
-- Security Traffic Analysis Vector Search - Step 2: Embeddings Tables
-- HTTP 요청 임베딩 및 리포트 지식베이스
-- ============================================================

USE security_traffic_analysis;

-- ============================================================
-- 1. HTTP 요청 임베딩 테이블
-- 기존 http_packets 테이블과 JOIN하여 사용
-- ============================================================

CREATE TABLE IF NOT EXISTS security_traffic_analysis.request_embeddings (
    packet_id UUID,

    -- 임베딩 대상 텍스트 (정규화됨)
    normalized_request String,  -- method + uri + body 조합
    request_hash String,         -- 중복 방지용 해시

    -- Vector Embedding
    request_embedding Array(Float32),

    -- 임베딩 메타데이터
    embedding_model LowCardinality(String) DEFAULT 'text-embedding-3-small',
    embedding_dim UInt16 DEFAULT 1536,

    -- Vector Similarity Index
    INDEX idx_request_embedding request_embedding
        TYPE vector_similarity('hnsw', 'cosineDistance')
        GRANULARITY 100000000,

    created_at DateTime DEFAULT now()
)
ENGINE = SharedMergeTree
ORDER BY (packet_id, created_at)
SETTINGS index_granularity = 8192
COMMENT 'HTTP 요청의 벡터 임베딩 저장소 - 유사 공격 패턴 탐지용';


-- ============================================================
-- 2. 버그 리포트 지식베이스 테이블
-- 시맨틱 검색 및 중복 리포트 탐지용
-- ============================================================

CREATE TABLE IF NOT EXISTS security_traffic_analysis.report_knowledge_base (
    report_id String,

    -- 리포트 내용
    title String,
    description String,
    reproduction_steps String,
    impact_description String,

    -- 분류
    vulnerability_type LowCardinality(String),
    affected_component String,
    affected_endpoints Array(String),

    -- 리포트 메타데이터
    reporter_id String,
    reported_date Date,

    -- 상태 및 처리
    status LowCardinality(String),  -- SUBMITTED, TRIAGED, ACCEPTED, REJECTED, DUPLICATE, FIXED
    priority LowCardinality(String) DEFAULT 'MEDIUM',  -- CRITICAL, HIGH, MEDIUM, LOW
    bounty_amount Decimal(10, 2) DEFAULT 0,
    assigned_to Nullable(String),

    -- Vector Embedding
    -- description + reproduction_steps를 합쳐서 임베딩
    content_embedding Array(Float32),

    -- 임베딩 메타데이터
    embedding_model LowCardinality(String) DEFAULT 'text-embedding-3-small',
    embedding_dim UInt16 DEFAULT 1536,

    -- Vector Similarity Index
    INDEX idx_content_embedding content_embedding
        TYPE vector_similarity('hnsw', 'cosineDistance')
        GRANULARITY 100000000,

    -- 타임스탬프
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now(),
    resolved_at Nullable(DateTime)
)
ENGINE = SharedReplacingMergeTree(updated_at)
ORDER BY (vulnerability_type, status, report_id)
SETTINGS index_granularity = 8192
COMMENT '버그 리포트 지식베이스 - 시맨틱 검색 및 중복 탐지용';


-- ============================================================
-- 3. 중복 리포트 링크 테이블
-- 중복으로 판단된 리포트 간의 관계 추적
-- ============================================================

CREATE TABLE IF NOT EXISTS security_traffic_analysis.duplicate_report_links (
    link_id UUID DEFAULT generateUUIDv4(),

    original_report_id String,    -- 원본 리포트
    duplicate_report_id String,   -- 중복 리포트

    similarity_score Float32,     -- 유사도 점수 (0~1, 높을수록 유사)
    detection_method LowCardinality(String),  -- VECTOR_SEARCH, MANUAL, RULE_BASED

    verified_by Nullable(String), -- 수동 검증자
    verified_at Nullable(DateTime),

    notes String DEFAULT '',

    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (original_report_id, similarity_score)
SETTINGS index_granularity = 8192
COMMENT '중복 리포트 관계 추적';


-- ============================================================
-- 4. 유틸리티 뷰: 요청 임베딩 통계
-- ============================================================

CREATE OR REPLACE VIEW security_traffic_analysis.v_embedding_stats AS
SELECT
    'request_embeddings' as table_name,
    count() as total_embeddings,
    count(DISTINCT embedding_model) as model_count,
    groupUniqArray(embedding_model) as models_used,
    min(created_at) as first_embedded,
    max(created_at) as last_embedded,
    formatReadableSize(sum(length(request_embedding) * 4)) as approx_storage_size
FROM security_traffic_analysis.request_embeddings

UNION ALL

SELECT
    'report_knowledge_base' as table_name,
    count() as total_embeddings,
    count(DISTINCT embedding_model) as model_count,
    groupUniqArray(embedding_model) as models_used,
    min(created_at) as first_embedded,
    max(created_at) as last_embedded,
    formatReadableSize(sum(length(content_embedding) * 4)) as approx_storage_size
FROM security_traffic_analysis.report_knowledge_base;


-- ============================================================
-- 5. 유틸리티 뷰: 리포트 대시보드
-- ============================================================

CREATE OR REPLACE VIEW security_traffic_analysis.v_report_dashboard AS
SELECT
    status,
    vulnerability_type,
    priority,
    count() as report_count,
    sum(bounty_amount) as total_bounty,
    round(avg(bounty_amount), 2) as avg_bounty,
    min(reported_date) as earliest_report,
    max(reported_date) as latest_report,
    countIf(resolved_at IS NOT NULL) as resolved_count,
    countIf(bounty_amount > 0) as paid_reports
FROM security_traffic_analysis.report_knowledge_base
GROUP BY status, vulnerability_type, priority
ORDER BY total_bounty DESC;


-- ============================================================
-- 6. 중복 리포트 탐지 함수
-- 새 리포트가 기존 리포트와 중복인지 확인
-- ============================================================

CREATE OR REPLACE FUNCTION security_traffic_analysis.isDuplicateReport AS (
    new_embedding,
    similarity_threshold
) -> (
    SELECT count() > 0
    FROM security_traffic_analysis.report_knowledge_base
    WHERE status IN ('ACCEPTED', 'FIXED', 'TRIAGED')
      AND cosineDistance(content_embedding, new_embedding) < similarity_threshold
);


-- ============================================================
-- 7. 테이블 확인
-- ============================================================

-- 생성된 테이블 목록
SELECT
    name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) as size,
    comment
FROM system.tables
WHERE database = 'security_traffic_analysis'
  AND name IN ('request_embeddings', 'report_knowledge_base', 'duplicate_report_links')
ORDER BY name
FORMAT PrettyCompactMonoBlock;

-- 인덱스 확인
SELECT
    table,
    name as index_name,
    type as index_type,
    expr as index_expression
FROM system.data_skipping_indices
WHERE database = 'security_traffic_analysis'
  AND table IN ('request_embeddings', 'report_knowledge_base')
ORDER BY table, name
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- 8. 성능 최적화 팁
-- ============================================================
/*
Vector Search 성능 최적화:

1. 임베딩 차원 선택:
   - text-embedding-3-small (1536 dim): 높은 정확도, 큰 저장공간
   - all-MiniLM-L6-v2 (384 dim): 낮은 저장공간, 빠른 검색
   - 용도에 따라 선택 (정확도 vs 성능)

2. HNSW 파라미터 튜닝:
   - GRANULARITY: 작을수록 정확하지만 느림 (기본: 100000000)
   - 대부분의 경우 기본값으로 충분

3. 쿼리 최적화:
   - LIMIT으로 결과 수 제한 (예: TOP 10)
   - WHERE 절로 후보군 사전 필터링
   - 파티션 키를 활용한 데이터 분할

4. 배치 임베딩 생성:
   - 대량 데이터는 배치로 처리
   - OpenAI API 요청 제한 고려 (RPM, TPM)

5. 캐싱 전략:
   - 자주 검색되는 쿼리는 결과 캐싱
   - Materialized View로 사전 계산

예시: 파티션 추가 (월별)
ALTER TABLE request_embeddings
    MODIFY SETTING partition_by = toYYYYMM(created_at);
*/


-- ============================================================
-- 다음 단계
-- ============================================================
-- 10-vector-demo-data.sql: 실제 벡터 데이터 생성
-- 11-vector-search-queries.sql: Vector Search 쿼리 실습
-- 12-vector-integration.sql: Python 통합 및 실전 활용
-- ============================================================
