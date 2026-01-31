-- ============================================================================
-- Bug Bounty Packet Analysis Platform - Step 5: Demo Data Generation
-- 버그바운티 패킷 분석 플랫폼 - Step 5: 데모 데이터 생성
-- ============================================================================
-- Created: 2026-01-31
-- 작성일: 2026-01-31
-- Purpose: Generate sample data for demo and testing
-- 목적: 데모 시연 및 테스트를 위한 샘플 데이터 생성
-- Expected time: ~5-10 seconds (depending on data volume)
-- 예상 시간: ~5-10초 (데이터 볼륨에 따라 다름)
-- ============================================================================

USE bug_bounty;

-- ============================================================================
-- 5.1 Normal Traffic Data Generation (Bulk)
-- 5.1 정상 트래픽 데이터 생성 (대량)
-- ============================================================================
-- Features: Generate 5,000 normal HTTP requests
-- 특징: 5,000개의 정상 HTTP 요청 생성
-- ============================================================================

INSERT INTO http_packets 
(
    session_id, report_id, participant_id, timestamp,
    request_method, request_uri, request_headers, request_body,
    response_status, response_headers, response_body, response_time_ms,
    source_ip, dest_ip, content_length, user_agent
)
SELECT
    concat('session-', toString(rand() % 500)) as session_id,
    if(rand() % 5 = 0, concat('BUG-2024-', toString(1000 + rand() % 200)), '') as report_id,
    concat('participant-', toString(rand() % 100)) as participant_id,
    
    now() - toIntervalSecond(rand() % 86400) as timestamp,
    
    arrayElement(['GET', 'GET', 'GET', 'POST', 'PUT', 'DELETE'], (rand() % 6) + 1) as request_method,
    
    arrayElement([
        '/api/users/profile',
        '/api/products/list',
        '/api/orders/recent',
        '/api/search?q=test',
        '/api/notifications',
        '/api/settings',
        '/health',
        '/api/v1/data'
    ], (rand() % 8) + 1) as request_uri,
    
    map('Content-Type', 'application/json', 'Accept', 'application/json') as request_headers,
    '{"page": 1, "limit": 20}' as request_body,
    
    arrayElement([200, 200, 200, 200, 201, 204, 400, 401, 404], (rand() % 9) + 1) as response_status,
    map('Content-Type', 'application/json') as response_headers,
    '{"status": "ok", "data": []}' as response_body,
    50 + rand() % 200 as response_time_ms,
    
    concat('192.168.', toString(rand() % 256), '.', toString(rand() % 256)) as source_ip,
    '10.0.0.1' as dest_ip,
    rand() % 5000 as content_length,
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' as user_agent

FROM numbers(5000);


-- ============================================================================
-- 5.2 Vulnerability Reproduction Scenario (SQL Injection Report)
-- 5.2 취약점 재현 시나리오 데이터 (SQL Injection 리포트)
-- ============================================================================
-- Features: Create attack sequence data for SQL Injection testing
-- 특징: SQL Injection 테스트를 위한 공격 시퀀스 데이터 생성
-- ============================================================================

-- SQL Injection 공격 시퀀스 - 패치 전
INSERT INTO http_packets 
(
    session_id, report_id, participant_id, timestamp,
    request_method, request_uri, request_headers, request_body,
    response_status, response_headers, response_body, response_time_ms,
    source_ip, dest_ip, content_length, user_agent
)
VALUES
    -- 탐색 단계
    ('sqli-session-001', 'BUG-2024-1234', 'researcher-alice', 
     now() - toIntervalHour(48), 'GET', '/api/users/1', 
     map('Content-Type', 'application/json'), '',
     200, map('Content-Type', 'application/json'), 
     '{"id": 1, "name": "John"}', 45,
     '10.20.30.40', '10.0.0.1', 100, 'BugBounty-Scanner/1.0'),
    
    -- SQL Injection 시도 1
    ('sqli-session-001', 'BUG-2024-1234', 'researcher-alice', 
     now() - toIntervalHour(48) + toIntervalSecond(30), 'GET', 
     '/api/users/1'' OR ''1''=''1', 
     map('Content-Type', 'application/json'), '',
     500, map('Content-Type', 'application/json'), 
     '{"error": "SQL syntax error near '' OR ''1''=''1"}', 120,
     '10.20.30.40', '10.0.0.1', 200, 'BugBounty-Scanner/1.0'),
    
    -- SQL Injection 시도 2 - UNION 기반
    ('sqli-session-001', 'BUG-2024-1234', 'researcher-alice', 
     now() - toIntervalHour(48) + toIntervalSecond(60), 'GET', 
     '/api/users/1 UNION SELECT * FROM users--', 
     map('Content-Type', 'application/json'), '',
     500, map('Content-Type', 'application/json'), 
     '{"error": "SQL syntax error", "details": "UNION not allowed"}', 150,
     '10.20.30.40', '10.0.0.1', 250, 'BugBounty-Scanner/1.0'),
    
    -- SQL Injection 성공 케이스
    ('sqli-session-001', 'BUG-2024-1234', 'researcher-alice', 
     now() - toIntervalHour(48) + toIntervalSecond(90), 'GET', 
     '/api/users/1;SELECT password FROM users WHERE id=1', 
     map('Content-Type', 'application/json'), '',
     200, map('Content-Type', 'application/json'), 
     '{"id": 1, "name": "John", "password_hash": "5f4dcc3b5aa765d61d8327deb882cf99"}', 200,
     '10.20.30.40', '10.0.0.1', 300, 'BugBounty-Scanner/1.0');


-- SQL Injection 공격 시퀀스 - 패치 후 (회귀 검증)
INSERT INTO http_packets 
(
    session_id, report_id, participant_id, timestamp,
    request_method, request_uri, request_headers, request_body,
    response_status, response_headers, response_body, response_time_ms,
    source_ip, dest_ip, content_length, user_agent
)
VALUES
    -- 패치 후 동일 공격 재시도
    ('sqli-session-002', 'BUG-2024-1234', 'researcher-alice', 
     now() - toIntervalHour(24), 'GET', 
     '/api/users/1'' OR ''1''=''1', 
     map('Content-Type', 'application/json'), '',
     400, map('Content-Type', 'application/json'), 
     '{"error": "Invalid input", "code": "VALIDATION_ERROR"}', 30,
     '10.20.30.40', '10.0.0.1', 100, 'BugBounty-Scanner/1.0'),
    
    ('sqli-session-002', 'BUG-2024-1234', 'researcher-alice', 
     now() - toIntervalHour(24) + toIntervalSecond(30), 'GET', 
     '/api/users/1;SELECT password FROM users WHERE id=1', 
     map('Content-Type', 'application/json'), '',
     400, map('Content-Type', 'application/json'), 
     '{"error": "Invalid input", "code": "VALIDATION_ERROR"}', 25,
     '10.20.30.40', '10.0.0.1', 100, 'BugBounty-Scanner/1.0');


-- ----------------------------------------------------------------------------
-- 3. 민감정보 노출 시나리오 데이터
-- ----------------------------------------------------------------------------

INSERT INTO http_packets 
(
    session_id, report_id, participant_id, timestamp,
    request_method, request_uri, request_headers, request_body,
    response_status, response_headers, response_body, response_time_ms,
    source_ip, dest_ip, content_length, user_agent
)
VALUES
    -- JWT 토큰 노출
    ('pii-session-001', 'BUG-2024-1500', 'researcher-bob', 
     now() - toIntervalHour(12), 'POST', '/api/auth/login', 
     map('Content-Type', 'application/json'), 
     '{"username": "test", "password": "test123"}',
     200, map('Content-Type', 'application/json'), 
     '{"token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9.TJVA95OrM7E2cBab30RMHrHDcEfxjoYZgeFONFh7HgQ", "user": {"email": "john.doe@example.com", "phone": "010-1234-5678"}}', 150,
     '10.30.40.50', '10.0.0.1', 500, 'Mozilla/5.0'),
    
    -- API Key 노출
    ('pii-session-002', 'BUG-2024-1501', 'researcher-bob', 
     now() - toIntervalHour(10), 'GET', '/api/settings/integrations', 
     map('Content-Type', 'application/json', 'Authorization', 'Bearer valid-token'), '',
     200, map('Content-Type', 'application/json'),
     '{"integrations": [{"name": "Slack", "api_key": "DEMO-TOKEN-NOT-REAL-xoxb-fake"}, {"name": "AWS", "api_key": "DEMO-KEY-NOT-REAL-AKIA-fake"}]}', 80,
     '10.30.40.50', '10.0.0.1', 300, 'Mozilla/5.0'),
    
    -- 신용카드 정보 노출
    ('pii-session-003', 'BUG-2024-1502', 'researcher-charlie', 
     now() - toIntervalHour(8), 'GET', '/api/orders/12345', 
     map('Content-Type', 'application/json'), '',
     200, map('Content-Type', 'application/json'), 
     '{"order_id": 12345, "payment": {"card_number": "4111-1111-1111-1111", "expiry": "12/25", "cvv": "123"}, "customer_email": "customer@test.com"}', 60,
     '10.40.50.60', '10.0.0.1', 400, 'Mozilla/5.0'),
    
    -- 복합 PII 노출 (심각)
    ('pii-session-004', 'BUG-2024-1503', 'researcher-charlie', 
     now() - toIntervalHour(6), 'GET', '/api/admin/users/export', 
     map('Content-Type', 'application/json'), '',
     200, map('Content-Type', 'application/json'), 
     '{"users": [{"id": 1, "email": "user1@company.com", "phone": "010-9876-5432", "api_key": "sk-proj-abcd1234efgh5678ijkl"}, {"id": 2, "email": "admin@company.com", "password_reset_token": "eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoiMiJ9.abc123"}]}', 200,
     '10.40.50.60', '10.0.0.1', 800, 'Mozilla/5.0');


-- ----------------------------------------------------------------------------
-- 4. Bruteforce 공격 시나리오 데이터
-- ----------------------------------------------------------------------------

INSERT INTO http_packets 
(
    session_id, report_id, participant_id, timestamp,
    request_method, request_uri, request_headers, request_body,
    response_status, response_headers, response_body, response_time_ms,
    source_ip, dest_ip, content_length, user_agent
)
SELECT
    'bruteforce-session-001' as session_id,
    '' as report_id,
    'attacker-001' as participant_id,
    
    now() - toIntervalMinute(5) + toIntervalSecond(number) as timestamp,
    
    'POST' as request_method,
    '/api/auth/login' as request_uri,
    map('Content-Type', 'application/json') as request_headers,
    concat('{"username": "admin", "password": "password', toString(number), '"}') as request_body,
    
    if(number = 150, 200, 401) as response_status,  -- 150번째에서 성공
    map('Content-Type', 'application/json') as response_headers,
    if(number = 150, '{"token": "success"}', '{"error": "Invalid credentials"}') as response_body,
    50 + rand() % 50 as response_time_ms,
    
    '192.168.100.100' as source_ip,
    '10.0.0.1' as dest_ip,
    200 as content_length,
    'python-requests/2.28.0' as user_agent

FROM numbers(200);


-- ----------------------------------------------------------------------------
-- 5. Scanner 공격 시나리오 데이터
-- ----------------------------------------------------------------------------

INSERT INTO http_packets 
(
    session_id, report_id, participant_id, timestamp,
    request_method, request_uri, request_headers, request_body,
    response_status, response_headers, response_body, response_time_ms,
    source_ip, dest_ip, content_length, user_agent
)
SELECT
    'scanner-session-001' as session_id,
    '' as report_id,
    'scanner-001' as participant_id,
    
    now() - toIntervalMinute(3) + toIntervalMillisecond(number * 100) as timestamp,
    
    'GET' as request_method,
    
    arrayElement([
        '/admin', '/admin/login', '/admin/config', '/admin/users',
        '/.env', '/.git/config', '/wp-admin', '/phpmyadmin',
        '/api/v1/admin', '/api/internal', '/api/debug', '/api/test',
        '/backup', '/backup.sql', '/database.sql', '/dump.sql',
        '/config.php', '/settings.php', '/wp-config.php',
        '/.aws/credentials', '/.ssh/id_rsa', '/etc/passwd',
        '/api/users/1', '/api/users/2', '/api/users/admin',
        '/graphql', '/api/graphql', '/__graphql',
        '/swagger', '/api-docs', '/openapi.json',
        '/actuator', '/actuator/health', '/actuator/env',
        '/metrics', '/prometheus', '/debug/pprof',
        concat('/api/items/', toString(number)),
        concat('/api/products/', toString(number)),
        concat('/files/', toString(number), '.pdf')
    ], (number % 40) + 1) as request_uri,
    
    map('Content-Type', 'application/json') as request_headers,
    '' as request_body,
    
    arrayElement([404, 404, 404, 403, 403, 500, 200], (rand() % 7) + 1) as response_status,
    map('Content-Type', 'application/json') as response_headers,
    '{"error": "Not found"}' as response_body,
    30 + rand() % 100 as response_time_ms,
    
    '192.168.200.200' as source_ip,
    '10.0.0.1' as dest_ip,
    100 as content_length,
    'Nikto/2.1.6' as user_agent

FROM numbers(150);


-- ----------------------------------------------------------------------------
-- 6. Enumeration 공격 시나리오 데이터
-- ----------------------------------------------------------------------------

INSERT INTO http_packets 
(
    session_id, report_id, participant_id, timestamp,
    request_method, request_uri, request_headers, request_body,
    response_status, response_headers, response_body, response_time_ms,
    source_ip, dest_ip, content_length, user_agent
)
SELECT
    'enum-session-001' as session_id,
    '' as report_id,
    'enumerator-001' as participant_id,
    
    now() - toIntervalMinute(4) + toIntervalMillisecond(number * 200) as timestamp,
    
    'GET' as request_method,
    concat('/api/users/', toString(number)) as request_uri,
    map('Content-Type', 'application/json', 'Authorization', 'Bearer stolen-token') as request_headers,
    '' as request_body,
    
    -- 일부 ID만 존재하는 것으로 시뮬레이션
    if(number % 7 = 0, 200, if(rand() % 3 = 0, 403, 404)) as response_status,
    map('Content-Type', 'application/json') as response_headers,
    if(number % 7 = 0, 
       concat('{"id": ', toString(number), ', "username": "user', toString(number), '", "email": "user', toString(number), '@example.com"}'),
       '{"error": "Not found"}'
    ) as response_body,
    40 + rand() % 60 as response_time_ms,
    
    '192.168.150.150' as source_ip,
    '10.0.0.1' as dest_ip,
    150 as content_length,
    'curl/7.68.0' as user_agent

FROM numbers(100);


-- ----------------------------------------------------------------------------
-- 7. EDoS 공격 시나리오 데이터
-- ----------------------------------------------------------------------------

INSERT INTO http_packets 
(
    session_id, report_id, participant_id, timestamp,
    request_method, request_uri, request_headers, request_body,
    response_status, response_headers, response_body, response_time_ms,
    source_ip, dest_ip, content_length, user_agent
)
SELECT
    'edos-session-001' as session_id,
    '' as report_id,
    'edos-attacker-001' as participant_id,
    
    now() - toIntervalMinute(2) + toIntervalSecond(number) as timestamp,
    
    'POST' as request_method,
    
    arrayElement([
        '/api/reports/export?format=csv&all=true',
        '/api/analytics/generate?range=all',
        '/api/backup/full',
        '/api/search?q=*&limit=10000',
        '/api/export/database'
    ], (number % 5) + 1) as request_uri,
    
    map('Content-Type', 'application/json') as request_headers,
    '{"include_all": true, "no_limit": true}' as request_body,
    
    200 as response_status,
    map('Content-Type', 'application/json') as response_headers,
    '{"status": "processing", "estimated_time": "300s"}' as response_body,
    
    5000 + rand() % 10000 as response_time_ms,  -- 5~15초 응답시간
    
    '192.168.250.250' as source_ip,
    '10.0.0.1' as dest_ip,
    5000000 + rand() % 10000000 as content_length,  -- 5~15MB
    'Apache-HttpClient/4.5.13' as user_agent

FROM numbers(80);


-- ----------------------------------------------------------------------------
-- 데이터 생성 확인
-- ----------------------------------------------------------------------------

SELECT '=== 데이터 생성 완료 ===' as message;

SELECT 
    'http_packets' as table_name,
    count() as total_rows,
    uniq(session_id) as unique_sessions,
    uniqIf(report_id, report_id != '') as unique_reports,
    uniq(participant_id) as unique_participants
FROM http_packets;

SELECT 
    '시나리오별 데이터 분포' as info,
    session_id,
    count() as packet_count
FROM http_packets
WHERE session_id LIKE '%session-001'
GROUP BY session_id
ORDER BY session_id;
