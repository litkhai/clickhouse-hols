-- ============================================================
-- ClickHouse Async Insert - 기본 파라미터 테스트 (각 1,000건)
-- ============================================================

-- 케이스 1: 동기 INSERT (baseline)
INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT
    number as id,
    rand() % 10000 as user_id,
    ['click', 'view', 'purchase', 'login', 'logout'][rand() % 5 + 1] as event_type,
    randomPrintableASCII(100) as payload,
    'case1_sync' as test_case
FROM numbers(1000)
SETTINGS async_insert = 0;

-- 케이스 2: async_insert=1, wait=1 (flush 대기)
INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT
    number + 100000 as id,
    rand() % 10000 as user_id,
    ['click', 'view', 'purchase', 'login', 'logout'][rand() % 5 + 1] as event_type,
    randomPrintableASCII(100) as payload,
    'case2_async_wait1' as test_case
FROM numbers(1000)
SETTINGS async_insert = 1, wait_for_async_insert = 1;

-- 케이스 3: async_insert=1, wait=0 (즉시 응답)
INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT
    number + 200000 as id,
    rand() % 10000 as user_id,
    ['click', 'view', 'purchase', 'login', 'logout'][rand() % 5 + 1] as event_type,
    randomPrintableASCII(100) as payload,
    'case3_async_wait0' as test_case
FROM numbers(1000)
SETTINGS async_insert = 1, wait_for_async_insert = 0;

-- 케이스 4: async_insert=1, wait=0, busy_timeout=200ms
INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT
    number + 300000 as id,
    rand() % 10000 as user_id,
    ['click', 'view', 'purchase', 'login', 'logout'][rand() % 5 + 1] as event_type,
    randomPrintableASCII(100) as payload,
    'case4_async_timeout200' as test_case
FROM numbers(1000)
SETTINGS async_insert = 1, wait_for_async_insert = 0, async_insert_busy_timeout_ms = 200;

-- 케이스 5: async_insert=1, wait=0, max_data_size=1MB
INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT
    number + 400000 as id,
    rand() % 10000 as user_id,
    ['click', 'view', 'purchase', 'login', 'logout'][rand() % 5 + 1] as event_type,
    randomPrintableASCII(100) as payload,
    'case5_async_maxsize1mb' as test_case
FROM numbers(1000)
SETTINGS async_insert = 1, wait_for_async_insert = 0, async_insert_max_data_size = 1048576;

-- 케이스 6: async_insert=1, wait=1, busy_timeout=200ms (빠른 대기)
INSERT INTO async_insert_test.test_logs (id, user_id, event_type, payload, test_case)
SELECT
    number + 500000 as id,
    rand() % 10000 as user_id,
    ['click', 'view', 'purchase', 'login', 'logout'][rand() % 5 + 1] as event_type,
    randomPrintableASCII(100) as payload,
    'case6_async_wait1_timeout200' as test_case
FROM numbers(1000)
SETTINGS async_insert = 1, wait_for_async_insert = 1, async_insert_busy_timeout_ms = 200;
