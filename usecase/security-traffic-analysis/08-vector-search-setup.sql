-- ============================================================
-- Bug Bounty Vector Search - Step 1: Setup
-- ClickHouse 24.8+ 필요 (Vector Search GA)
-- ============================================================

-- ============================================================
-- Vector Search 개념
-- ============================================================
-- Vector Search (벡터 검색)는 고차원 벡터 공간에서 유사도를 기반으로
-- 데이터를 검색하는 기술입니다. 전통적인 키워드 기반 검색과 달리,
-- 의미적(semantic) 유사성을 찾을 수 있습니다.
--
-- 주요 사용 사례:
-- 1. 유사 공격 패턴 탐지: 새로운 요청이 알려진 공격과 얼마나 유사한지
-- 2. 중복 리포트 탐지: 새 버그 리포트가 기존 리포트와 중복인지
-- 3. 시맨틱 검색: 자연어로 관련 버그 리포트 찾기
-- 4. 이상 탐지: 정상 패턴에서 벗어난 요청 찾기
--
-- ClickHouse Vector Search 특징:
-- - HNSW (Hierarchical Navigable Small World) 알고리즘 사용
-- - cosineDistance, L2Distance 등 다양한 거리 함수 지원
-- - SharedMergeTree 엔진에서 동작
-- ============================================================

USE bug_bounty;

-- ============================================================
-- 1. 공격 패턴 시그니처 테이블
-- 알려진 취약점 패턴을 임베딩으로 저장하여 유사 공격 탐지
-- ============================================================

-- 시그니처 테이블 생성
CREATE TABLE IF NOT EXISTS bug_bounty.attack_signatures (
    signature_id UUID DEFAULT generateUUIDv4(),

    -- 패턴 메타데이터
    pattern_name String,                      -- 패턴 이름 (예: "SQL Injection - OR bypass")
    pattern_description String,               -- 상세 설명
    category LowCardinality(String),          -- SQLi, XSS, SSRF, IDOR, etc.

    -- 취약점 분류
    cwe_id String,                            -- CWE-89 (SQLi), CWE-79 (XSS), etc.
    cvss_score Float32,                       -- 0.0 ~ 10.0 (위험도)
    severity LowCardinality(String),          -- CRITICAL, HIGH, MEDIUM, LOW

    -- 공격 패턴 정보
    sample_payload String,                    -- 샘플 페이로드 (마스킹됨)
    attack_vector LowCardinality(String),     -- GET_PARAM, POST_BODY, HEADER, COOKIE
    common_targets Array(String),             -- 일반적인 취약 엔드포인트들

    -- Vector Embedding
    -- OpenAI text-embedding-3-small (1536 dimensions) 또는
    -- Sentence Transformers all-MiniLM-L6-v2 (384 dimensions) 사용 가능
    payload_embedding Array(Float32),

    -- Vector Similarity Index
    -- HNSW: 빠른 근사 최근접 이웃 검색
    -- cosineDistance: 벡터 간 각도 기반 유사도 (0=동일, 2=정반대)
    INDEX idx_payload_embedding payload_embedding
        TYPE vector_similarity('hnsw', 'cosineDistance')
        GRANULARITY 100000000,

    -- 메타데이터
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now(),
    is_active Bool DEFAULT true
)
ENGINE = SharedMergeTree
ORDER BY (category, cvss_score, signature_id)
SETTINGS index_granularity = 8192
COMMENT '알려진 공격 패턴의 벡터 임베딩 저장소';


-- ============================================================
-- 2. 기본 공격 패턴 샘플 (임베딩 없이 메타데이터만)
-- 실제 사용 시에는 임베딩 API를 통해 벡터를 생성해야 합니다
-- ============================================================

-- 샘플 데이터 삽입 (실제 임베딩은 10-vector-demo-data.sql에서)
INSERT INTO bug_bounty.attack_signatures
(pattern_name, pattern_description, category, cwe_id, cvss_score, severity,
 sample_payload, attack_vector, common_targets, payload_embedding)
VALUES
('SQL Injection - OR bypass',
 '항상 참이 되는 OR 조건을 삽입하여 인증 우회',
 'SQLi', 'CWE-89', 9.8, 'CRITICAL',
 "username' OR '1'='1' --",
 'POST_BODY',
 ['/login', '/admin/login', '/api/auth'],
 []), -- 빈 배열 (10번 파일에서 채움)

('SQL Injection - UNION attack',
 'UNION SELECT를 사용한 데이터 추출',
 'SQLi', 'CWE-89', 9.5, 'CRITICAL',
 "id=1 UNION SELECT password FROM users--",
 'GET_PARAM',
 ['/api/users', '/products', '/search'],
 []),

('XSS - Script tag injection',
 '<script> 태그를 삽입하여 악의적 코드 실행',
 'XSS', 'CWE-79', 7.1, 'HIGH',
 "<script>alert('XSS')</script>",
 'GET_PARAM',
 ['/search', '/comment', '/profile'],
 []),

('XSS - Event handler injection',
 'HTML 이벤트 핸들러를 통한 코드 실행',
 'XSS', 'CWE-79', 7.1, 'HIGH',
 "<img src=x onerror=alert(1)>",
 'POST_BODY',
 ['/comment', '/feedback', '/contact'],
 []),

('SSRF - Internal network access',
 '내부 네트워크 리소스에 접근 시도',
 'SSRF', 'CWE-918', 8.5, 'HIGH',
 "url=http://localhost:8080/admin",
 'GET_PARAM',
 ['/api/fetch', '/proxy', '/webhook'],
 []),

('Path Traversal - Directory access',
 '상위 디렉토리 접근을 통한 파일 읽기',
 'Path Traversal', 'CWE-22', 7.5, 'HIGH',
 "file=../../etc/passwd",
 'GET_PARAM',
 ['/download', '/view', '/api/files'],
 []),

('IDOR - Sequential ID enumeration',
 '순차적 ID를 통한 타인 데이터 접근',
 'IDOR', 'CWE-639', 6.5, 'MEDIUM',
 "/api/user/1234/profile (incrementing ID)",
 'URI',
 ['/api/user/', '/api/order/', '/api/document/'],
 []),

('Command Injection - Shell metacharacters',
 '쉘 메타문자를 사용한 명령어 실행',
 'Command Injection', 'CWE-78', 9.8, 'CRITICAL',
 "file.txt; cat /etc/passwd",
 'POST_BODY',
 ['/api/upload', '/admin/backup', '/tools/convert'],
 []);


-- ============================================================
-- 3. 유틸리티 뷰: 시그니처 통계
-- ============================================================

CREATE OR REPLACE VIEW bug_bounty.v_signature_stats AS
SELECT
    category,
    count() as pattern_count,
    round(avg(cvss_score), 2) as avg_cvss,
    countIf(severity = 'CRITICAL') as critical_count,
    countIf(severity = 'HIGH') as high_count,
    countIf(severity = 'MEDIUM') as medium_count,
    countIf(severity = 'LOW') as low_count,
    countIf(is_active) as active_count
FROM bug_bounty.attack_signatures
GROUP BY category
ORDER BY avg_cvss DESC;


-- ============================================================
-- 4. 테이블 확인
-- ============================================================

-- 생성된 테이블 확인
SELECT
    name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) as size
FROM system.tables
WHERE database = 'bug_bounty'
  AND name = 'attack_signatures'
FORMAT PrettyCompactMonoBlock;

-- 삽입된 시그니처 확인
SELECT
    category,
    pattern_name,
    severity,
    cvss_score,
    sample_payload
FROM bug_bounty.attack_signatures
ORDER BY cvss_score DESC
FORMAT PrettyCompactMonoBlock;

-- 시그니처 통계 확인
SELECT * FROM bug_bounty.v_signature_stats
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- 다음 단계
-- ============================================================
-- 09-vector-embeddings-tables.sql: 요청 임베딩 및 리포트 테이블 생성
-- 10-vector-demo-data.sql: 실제 벡터 데이터 생성
-- 11-vector-search-queries.sql: Vector Search 쿼리 실습
-- 12-vector-integration.sql: Python 통합 및 실전 활용
-- ============================================================
