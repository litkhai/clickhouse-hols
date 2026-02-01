-- ============================================================
-- Bug Bounty Vector Search - Step 3: Demo Data
-- Vector Embeddings 생성 및 샘플 데이터 삽입
-- ============================================================

USE bug_bounty;

-- ============================================================
-- Mock Embedding 함수
-- 실제 운영 환경에서는 OpenAI API나 Sentence Transformers 사용
-- 여기서는 데모용으로 패턴 기반 벡터 생성
-- ============================================================

-- SQLi 패턴 벡터 생성 함수 (유사한 공격은 유사한 벡터를 가짐)
CREATE OR REPLACE FUNCTION bug_bounty.generateSQLiVector AS (seed) -> (
    arrayMap(i -> sin(seed * i * 0.1) * 0.5 + 0.5, range(1, 1537))
);

-- XSS 패턴 벡터 생성 함수
CREATE OR REPLACE FUNCTION bug_bounty.generateXSSVector AS (seed) -> (
    arrayMap(i -> cos(seed * i * 0.15) * 0.5 + 0.5, range(1, 1537))
);

-- SSRF 패턴 벡터 생성 함수
CREATE OR REPLACE FUNCTION bug_bounty.generateSSRFVector AS (seed) -> (
    arrayMap(i -> sin(seed * i * 0.2) * cos(i * 0.1) * 0.5 + 0.5, range(1, 1537))
);

-- 일반 벡터 생성 함수 (해시 기반)
CREATE OR REPLACE FUNCTION bug_bounty.generateMockEmbedding AS (text, dim) -> (
    arrayMap(i -> (cityHash64(text) % (i * 1000 + 1)) / ((i * 1000 + 1) * 1.0), range(1, dim + 1))
);


-- ============================================================
-- 1. attack_signatures 테이블에 벡터 데이터 업데이트
-- ============================================================

-- 기존 시그니처에 임베딩 추가
UPDATE bug_bounty.attack_signatures
SET payload_embedding = bug_bounty.generateSQLiVector(cityHash64(pattern_name))
WHERE category = 'SQLi' AND length(payload_embedding) = 0;

UPDATE bug_bounty.attack_signatures
SET payload_embedding = bug_bounty.generateXSSVector(cityHash64(pattern_name))
WHERE category = 'XSS' AND length(payload_embedding) = 0;

UPDATE bug_bounty.attack_signatures
SET payload_embedding = bug_bounty.generateSSRFVector(cityHash64(pattern_name))
WHERE category = 'SSRF' AND length(payload_embedding) = 0;

UPDATE bug_bounty.attack_signatures
SET payload_embedding = bug_bounty.generateMockEmbedding(pattern_name, 1536)
WHERE length(payload_embedding) = 0;


-- 추가 공격 패턴 삽입
INSERT INTO bug_bounty.attack_signatures
(pattern_name, pattern_description, category, cwe_id, cvss_score, severity,
 sample_payload, attack_vector, common_targets, payload_embedding)
VALUES
('SQL Injection - Time-based blind',
 'SLEEP 함수를 사용한 시간 기반 블라인드 SQLi',
 'SQLi', 'CWE-89', 8.5, 'HIGH',
 "id=1' AND SLEEP(5)--",
 'GET_PARAM',
 ['/api/search', '/product'],
 bug_bounty.generateSQLiVector(1234)),

('SQL Injection - Error-based',
 '에러 메시지를 통한 데이터베이스 정보 추출',
 'SQLi', 'CWE-89', 8.0, 'HIGH',
 "id=1' AND 1=CONVERT(int, (SELECT @@version))--",
 'GET_PARAM',
 ['/api/details', '/view'],
 bug_bounty.generateSQLiVector(5678)),

('XSS - DOM-based',
 'DOM 조작을 통한 클라이언트 측 XSS',
 'XSS', 'CWE-79', 6.5, 'MEDIUM',
 "#<img src=x onerror=alert(document.cookie)>",
 'URI',
 ['/dashboard', '/profile'],
 bug_bounty.generateXSSVector(9012)),

('LDAP Injection',
 'LDAP 쿼리 조작을 통한 인증 우회',
 'LDAP Injection', 'CWE-90', 8.0, 'HIGH',
 "username=*)(uid=*))(|(uid=*",
 'POST_BODY',
 ['/ldap/auth', '/directory/search'],
 bug_bounty.generateMockEmbedding('ldap', 1536)),

('XML External Entity (XXE)',
 '외부 엔티티를 통한 파일 읽기 또는 SSRF',
 'XXE', 'CWE-611', 8.5, 'HIGH',
 '<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><foo>&xxe;</foo>',
 'POST_BODY',
 ['/api/upload', '/xml/parse'],
 bug_bounty.generateMockEmbedding('xxe', 1536));


-- ============================================================
-- 2. request_embeddings 샘플 데이터 생성
-- 기존 http_packets에서 일부 선택하여 임베딩 추가
-- ============================================================

-- SQLi 공격 요청 임베딩
INSERT INTO bug_bounty.request_embeddings
(packet_id, normalized_request, request_hash, request_embedding, embedding_model, embedding_dim)
SELECT
    packet_id,
    concat(request_method, ' ', request_uri, '\n', substring(request_body, 1, 500)) as normalized_request,
    hex(MD5(concat(request_method, request_uri, request_body))) as request_hash,
    bug_bounty.generateSQLiVector(cityHash64(packet_id)) as request_embedding,
    'mock-text-embedding-3-small' as embedding_model,
    1536 as embedding_dim
FROM bug_bounty.http_packets
WHERE report_id = 'BUG-2024-001'  -- SQL Injection 리포트
LIMIT 50;

-- XSS 공격 요청 임베딩
INSERT INTO bug_bounty.request_embeddings
(packet_id, normalized_request, request_hash, request_embedding, embedding_model, embedding_dim)
SELECT
    packet_id,
    concat(request_method, ' ', request_uri, '\n', substring(response_body, 1, 500)) as normalized_request,
    hex(MD5(concat(request_method, request_uri, response_body))) as request_hash,
    bug_bounty.generateXSSVector(cityHash64(packet_id)) as request_embedding,
    'mock-text-embedding-3-small' as embedding_model,
    1536 as embedding_dim
FROM bug_bounty.http_packets
WHERE request_uri LIKE '%<script%' OR response_body LIKE '%<script%'
LIMIT 30;

-- 정상 트래픽 임베딩 (다른 패턴)
INSERT INTO bug_bounty.request_embeddings
(packet_id, normalized_request, request_hash, request_embedding, embedding_model, embedding_dim)
SELECT
    packet_id,
    concat(request_method, ' ', request_uri) as normalized_request,
    hex(MD5(concat(request_method, request_uri))) as request_hash,
    bug_bounty.generateMockEmbedding(packet_id::String, 1536) as request_embedding,
    'mock-text-embedding-3-small' as embedding_model,
    1536 as embedding_dim
FROM bug_bounty.http_packets
WHERE report_id = ''  -- 정상 트래픽
  AND request_uri NOT LIKE '%<%'
  AND request_uri NOT LIKE '%SELECT%'
LIMIT 100;


-- ============================================================
-- 3. report_knowledge_base 샘플 데이터 생성
-- ============================================================

INSERT INTO bug_bounty.report_knowledge_base
(report_id, title, description, reproduction_steps, impact_description,
 vulnerability_type, affected_component, affected_endpoints,
 reporter_id, reported_date, status, priority, bounty_amount,
 content_embedding, embedding_model, embedding_dim)
VALUES
-- SQL Injection 리포트
('RPT-2024-001',
 'SQL Injection in User Login Endpoint',
 'The login endpoint is vulnerable to SQL injection attacks. By manipulating the username parameter with SQL metacharacters, an attacker can bypass authentication.',
 '1. Navigate to /login\n2. Enter username: admin'' OR ''1''=''1\n3. Enter any password\n4. Click login\n5. Successfully logged in as admin',
 'CRITICAL: Complete authentication bypass allows unauthorized access to admin accounts and sensitive data.',
 'SQLi',
 'Authentication Module',
 ['/api/login', '/auth/validate'],
 'hunter_001', today() - 30, 'FIXED', 'CRITICAL', 5000.00,
 bug_bounty.generateSQLiVector(1001), 'mock-text-embedding-3-small', 1536),

('RPT-2024-002',
 'SQL Injection in Search Function',
 'The search endpoint does not properly sanitize user input, allowing SQL injection through the query parameter.',
 '1. Go to /search\n2. Enter: test'' UNION SELECT password FROM users--\n3. Submit search\n4. Database information leaked in results',
 'HIGH: Allows extraction of sensitive database information including user credentials.',
 'SQLi',
 'Search Module',
 ['/api/search', '/products/search'],
 'hunter_002', today() - 25, 'ACCEPTED', 'HIGH', 3000.00,
 bug_bounty.generateSQLiVector(1002), 'mock-text-embedding-3-small', 1536),

-- XSS 리포트
('RPT-2024-003',
 'Reflected XSS in Comment Section',
 'User comments are reflected in the page without proper sanitization, allowing script injection.',
 '1. Navigate to /blog/post/123\n2. Submit comment: <script>alert(document.cookie)</script>\n3. Page reloads and script executes\n4. User cookies stolen',
 'MEDIUM: Allows stealing user session cookies and performing actions on their behalf.',
 'XSS',
 'Comment System',
 ['/blog/comment', '/api/comments'],
 'hunter_003', today() - 20, 'FIXED', 'MEDIUM', 1500.00,
 bug_bounty.generateXSSVector(2001), 'mock-text-embedding-3-small', 1536),

('RPT-2024-004',
 'Stored XSS in User Profile',
 'The user profile bio field allows HTML tags and executes JavaScript when other users view the profile.',
 '1. Go to /profile/edit\n2. Set bio: <img src=x onerror=alert(1)>\n3. Save profile\n4. Other users viewing profile trigger the payload',
 'HIGH: Persistent XSS that affects all users viewing the malicious profile.',
 'XSS',
 'User Profile',
 ['/profile/update', '/api/user/bio'],
 'hunter_003', today() - 18, 'TRIAGED', 'HIGH', 2500.00,
 bug_bounty.generateXSSVector(2002), 'mock-text-embedding-3-small', 1536),

-- SSRF 리포트
('RPT-2024-005',
 'SSRF in URL Fetch Feature',
 'The URL fetch endpoint allows access to internal network resources without validation.',
 '1. Navigate to /api/fetch\n2. Submit URL: http://localhost:8080/admin\n3. Internal admin panel content returned\n4. Access to internal services confirmed',
 'CRITICAL: Allows mapping and accessing internal network resources from external attacker.',
 'SSRF',
 'URL Fetch Module',
 ['/api/fetch', '/proxy'],
 'hunter_004', today() - 15, 'ACCEPTED', 'CRITICAL', 4000.00,
 bug_bounty.generateSSRFVector(3001), 'mock-text-embedding-3-small', 1536),

-- IDOR 리포트
('RPT-2024-006',
 'IDOR in User API Endpoint',
 'User information can be accessed by incrementing user IDs without authorization check.',
 '1. Authenticate as user ID 100\n2. Request /api/user/101/profile\n3. Receive other user data without authorization',
 'MEDIUM: Allows unauthorized access to other users personal information.',
 'IDOR',
 'User API',
 ['/api/user/', '/api/profile/'],
 'hunter_005', today() - 10, 'FIXED', 'MEDIUM', 1000.00,
 bug_bounty.generateMockEmbedding('idor_user', 1536), 'mock-text-embedding-3-small', 1536),

-- 중복 리포트 (RPT-2024-001과 유사)
('RPT-2024-007',
 'Authentication Bypass via SQL Injection',
 'The authentication system can be bypassed using SQL injection in the login form.',
 '1. Open login page\n2. Username: admin'' OR 1=1--\n3. Password: anything\n4. Successfully bypass authentication',
 'CRITICAL: Complete bypass of authentication mechanism.',
 'SQLi',
 'Authentication Module',
 ['/login', '/api/auth'],
 'hunter_006', today() - 5, 'DUPLICATE', 'CRITICAL', 0.00,
 bug_bounty.generateSQLiVector(1003), 'mock-text-embedding-3-small', 1536),

-- Path Traversal
('RPT-2024-008',
 'Path Traversal in File Download',
 'The file download endpoint allows accessing arbitrary files using path traversal.',
 '1. Request /api/download?file=../../etc/passwd\n2. System file contents returned\n3. Sensitive files accessible',
 'HIGH: Allows reading arbitrary files from the server filesystem.',
 'Path Traversal',
 'File Download',
 ['/api/download', '/files/get'],
 'hunter_007', today() - 3, 'TRIAGED', 'HIGH', 2000.00,
 bug_bounty.generateMockEmbedding('path_traversal', 1536), 'mock-text-embedding-3-small', 1536);


-- ============================================================
-- 4. 중복 리포트 링크 데이터
-- ============================================================

INSERT INTO bug_bounty.duplicate_report_links
(original_report_id, duplicate_report_id, similarity_score, detection_method, verified_by, verified_at, notes)
VALUES
('RPT-2024-001', 'RPT-2024-007', 0.95, 'VECTOR_SEARCH', 'admin', now() - INTERVAL 2 DAY,
 'Both reports describe SQL injection in login endpoint. RPT-2024-001 was reported first.');


-- ============================================================
-- 5. 데이터 검증
-- ============================================================

-- attack_signatures 확인
SELECT
    'attack_signatures' as table_name,
    count() as total_rows,
    countIf(length(payload_embedding) > 0) as with_embedding,
    countIf(length(payload_embedding) = 0) as without_embedding
FROM bug_bounty.attack_signatures
FORMAT PrettyCompactMonoBlock;

-- request_embeddings 확인
SELECT
    'request_embeddings' as table_name,
    count() as total_rows,
    count(DISTINCT embedding_model) as model_count,
    formatReadableSize(sum(length(request_embedding) * 4)) as storage_size
FROM bug_bounty.request_embeddings
FORMAT PrettyCompactMonoBlock;

-- report_knowledge_base 확인
SELECT
    'report_knowledge_base' as table_name,
    count() as total_reports,
    status,
    vulnerability_type,
    count() as count_per_type
FROM bug_bounty.report_knowledge_base
GROUP BY status, vulnerability_type
ORDER BY count_per_type DESC
FORMAT PrettyCompactMonoBlock;

-- 임베딩 벡터 차원 확인
SELECT
    'Vector Dimensions' as info,
    length(payload_embedding) as attack_sig_dim,
    (SELECT length(request_embedding) FROM bug_bounty.request_embeddings LIMIT 1) as request_emb_dim,
    (SELECT length(content_embedding) FROM bug_bounty.report_knowledge_base LIMIT 1) as report_emb_dim
FROM bug_bounty.attack_signatures
LIMIT 1
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- 6. 간단한 유사도 테스트
-- ============================================================

-- SQLi 공격들 간의 유사도 확인 (낮은 거리 = 높은 유사도)
SELECT
    a1.pattern_name as pattern_1,
    a2.pattern_name as pattern_2,
    round(cosineDistance(a1.payload_embedding, a2.payload_embedding), 4) as distance,
    round(1 - cosineDistance(a1.payload_embedding, a2.payload_embedding), 4) as similarity
FROM bug_bounty.attack_signatures a1
CROSS JOIN bug_bounty.attack_signatures a2
WHERE a1.category = 'SQLi' AND a2.category = 'SQLi'
  AND a1.signature_id < a2.signature_id
ORDER BY distance ASC
LIMIT 5
FORMAT PrettyCompactMonoBlock;

-- 중복 리포트 유사도 확인
SELECT
    r1.report_id,
    r1.title,
    r2.report_id as similar_report,
    r2.title as similar_title,
    round(cosineDistance(r1.content_embedding, r2.content_embedding), 4) as distance
FROM bug_bounty.report_knowledge_base r1
CROSS JOIN bug_bounty.report_knowledge_base r2
WHERE r1.report_id = 'RPT-2024-001'
  AND r2.report_id != r1.report_id
ORDER BY distance ASC
LIMIT 3
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- 다음 단계
-- ============================================================
-- 11-vector-search-queries.sql: 다양한 Vector Search 쿼리 실습
-- 12-vector-integration.sql: Python 통합 및 실전 활용
-- ============================================================
