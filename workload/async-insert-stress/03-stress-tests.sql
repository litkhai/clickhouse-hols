-- ============================================================
-- ClickHouse Async Insert - 고강도 스트레스 테스트
-- ============================================================

-- ============================================================
-- 대용량 테스트 (각 100,000건)
-- ============================================================

-- 대용량 테스트: 10만 건, async_insert=1, wait=0
INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT
    number + 1000000 as id,
    rand() % 10000 as user_id,
    ['click', 'view', 'purchase', 'login', 'logout'][rand() % 5 + 1] as event_type,
    randomPrintableASCII(500) as payload,
    'stress_100k_wait0' as test_case
FROM numbers(100000)
SETTINGS async_insert = 1, wait_for_async_insert = 0;

-- 대용량 테스트: 10만 건, async_insert=1, wait=1
INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT
    number + 2000000 as id,
    rand() % 10000 as user_id,
    ['click', 'view', 'purchase', 'login', 'logout'][rand() % 5 + 1] as event_type,
    randomPrintableASCII(500) as payload,
    'stress_100k_wait1' as test_case
FROM numbers(100000)
SETTINGS async_insert = 1, wait_for_async_insert = 1;

-- ============================================================
-- 연속 INSERT 테스트 (빠른 연속 실행)
-- ============================================================

INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT number + 3000000, rand() % 10000, 'click', 'rapid_test', 'rapid_insert_batch1'
FROM numbers(100)
SETTINGS async_insert = 1, wait_for_async_insert = 0;

INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT number + 3000100, rand() % 10000, 'click', 'rapid_test', 'rapid_insert_batch2'
FROM numbers(100)
SETTINGS async_insert = 1, wait_for_async_insert = 0;

INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT number + 3000200, rand() % 10000, 'click', 'rapid_test', 'rapid_insert_batch3'
FROM numbers(100)
SETTINGS async_insert = 1, wait_for_async_insert = 0;

INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT number + 3000300, rand() % 10000, 'click', 'rapid_test', 'rapid_insert_batch4'
FROM numbers(100)
SETTINGS async_insert = 1, wait_for_async_insert = 0;

INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT number + 3000400, rand() % 10000, 'click', 'rapid_test', 'rapid_insert_batch5'
FROM numbers(100)
SETTINGS async_insert = 1, wait_for_async_insert = 0;
