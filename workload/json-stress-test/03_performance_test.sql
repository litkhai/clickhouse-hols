-- ============================================
-- JSON 극한 테스트 - Phase 3: 성능 테스트 결과
-- ============================================

-- ============================================
-- 성능 테스트 결과 요약
-- ============================================

/*
============================================
테스트 환경
============================================
- 테이블: perf_test_large
- 설정: JSON(max_dynamic_paths=5000)
- 총 행 수: 6,100
- 필드 수: 5,000개/행
- 디스크 크기: 2.10 MiB

============================================
Dynamic vs Shared Path 분포
============================================
┌─dynamic_count─┬─shared_count─┬─rows─┐
│          1000 │         4000 │  600 │
│          1000 │            0 │ 5000 │
│          1000 │         9000 │  500 │
└───────────────┴──────────────┴──────┘

============================================
성능 측정 결과 ⭐
============================================

TEST 1: Dynamic Path 읽기 (f_0, f_500, f_999, f_100)
----------------------------------------------
- 쿼리 시간: 32ms
- 읽은 행: 6,100
- 읽은 데이터: 405.08 KiB
- 메모리 사용: 13.36 MiB

TEST 2: Shared Path 읽기 (f_1000, f_2500, f_4999, f_3000)
----------------------------------------------
- 쿼리 시간: 170ms
- 읽은 행: 6,100
- 읽은 데이터: 248.83 KiB
- 메모리 사용: 45.57 MiB

============================================
성능 비교 분석 ⭐⭐⭐
============================================

| 항목 | Dynamic Path | Shared Path | 차이 |
|------|--------------|-------------|------|
| 쿼리 시간 | 32ms | 170ms | 5.3배 느림 |
| 메모리 사용 | 13.36 MiB | 45.57 MiB | 3.4배 더 사용 |
| 읽은 데이터 | 405.08 KiB | 248.83 KiB | - |

결론:
- Shared Path 읽기가 Dynamic Path보다 약 5.3배 느림
- Shared Path 읽기가 메모리를 약 3.4배 더 사용
- 자주 쿼리하는 필드는 반드시 Dynamic Path로 유지해야 함
*/

-- ============================================
-- 실행된 쿼리들
-- ============================================

-- Dynamic path 읽기 테스트
SELECT 
    count(),
    sum(data.f_0::Int64) as sum_f0,
    sum(data.f_500::Int64) as sum_f500,
    sum(data.f_999::Int64) as sum_f999,
    avg(data.f_100::Int64) as avg_f100
FROM json_stress_test.perf_test_large;

-- Shared path 읽기 테스트
SELECT 
    count(),
    sum(data.f_1000::Int64) as sum_f1000,
    sum(data.f_2500::Int64) as sum_f2500,
    sum(data.f_4999::Int64) as sum_f4999,
    avg(data.f_3000::Int64) as avg_f3000
FROM json_stress_test.perf_test_large;

-- 쿼리 로그 확인
SELECT 
    query,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as read_size,
    formatReadableSize(memory_usage) as memory
FROM clusterAllReplicas('default', system.query_log)
WHERE (query LIKE '%sum_f0%' OR query LIKE '%sum_f1000%')
    AND type = 'QueryFinish'
    AND event_time > now() - INTERVAL 5 MINUTE
ORDER BY event_time DESC
LIMIT 4;
