-- ============================================================
-- ClickHouse Async Insert - 결과 확인 쿼리
-- ClickHouse Async Insert - Result Verification Queries
-- ============================================================

-- flush 대기 (3초)
-- Wait for flush (3 seconds)
SELECT sleep(3);

-- 테스트 케이스별 결과 요약
-- Summary of results by test case
SELECT
    test_case,
    count() as actual_rows,
    CASE
        WHEN test_case LIKE 'stress%' THEN 100000
        WHEN test_case LIKE 'rapid%' THEN 100
        ELSE 1000
    END as expected_rows,
    round(count() / CASE
        WHEN test_case LIKE 'stress%' THEN 100000
        WHEN test_case LIKE 'rapid%' THEN 100
        ELSE 1000
    END * 100, 4) as success_rate_pct,
    countDistinct(id) as distinct_ids
FROM async_insert_test.test_logs
GROUP BY test_case
ORDER BY test_case;

-- 전체 데이터 건수 확인
-- Check total record count
SELECT
    count() as total_rows,
    countDistinct(id) as distinct_ids,
    countDistinct(test_case) as test_cases
FROM async_insert_test.test_logs;
