-- ============================================================================
-- Full-Text Search Lab · Step 3: Baseline Search (no full-text index)
-- 풀텍스트 검색 실습 · Step 3: 베이스라인 검색 (풀텍스트 인덱스 없이)
-- ============================================================================
-- Goal: establish ground-truth performance and recall on tickets_noidx.
--       Every later step is judged against these numbers.
--
-- Run each query block in turn and watch the row count + elapsed time at the
-- bottom of clickhouse-client output. Copy the timings into the result table
-- printed by 04-index-comparison.sql.
-- ============================================================================

-- Make sure we always read every part (no part-level cache) for honest timing.
-- 정직한 측정을 위해 part-level 캐시 미적용.
SET use_query_cache = 0;
SET use_uncompressed_cache = 0;

SELECT '=== 3.1 LIKE — simple substring ===' AS section;
-- ----------------------------------------------------------------------------
-- 3.1 The plainest search any user types first: LIKE '%term%'
-- 3.1 가장 흔히 쓰는 검색: LIKE '%term%'
-- ----------------------------------------------------------------------------
-- This forces a full column scan. Korean works fine because LIKE is byte-aware.
-- Expect: hundreds of ms on a 1M-row table per query.
SELECT count() AS hits
FROM support_search.tickets_noidx
WHERE body LIKE '%결제 실패%';

SELECT count() AS hits
FROM support_search.tickets_noidx
WHERE body LIKE '%PAYMENT_DECLINED%';

SELECT '=== 3.2 position() — same idea, slightly faster ===' AS section;
-- ----------------------------------------------------------------------------
-- 3.2 position() returns the byte offset; non-zero means found.
-- 3.2 position()는 바이트 오프셋을 반환. 0이 아니면 발견.
-- ----------------------------------------------------------------------------
SELECT count() AS hits
FROM support_search.tickets_noidx
WHERE position(body, '결제 실패') > 0;

SELECT '=== 3.3 multiSearchAny — OR of many needles in one pass ===' AS section;
-- ----------------------------------------------------------------------------
-- 3.3 multiSearchAny: matches if ANY needle is found. Single SIMD pass.
-- 3.3 multiSearchAny: 여러 needle 중 하나라도 매치되면 true. SIMD 한 번에 처리.
-- ----------------------------------------------------------------------------
SELECT count() AS hits
FROM support_search.tickets_noidx
WHERE multiSearchAny(body, ['결제 실패','결제 안됨','결제가 안 됩니다','PAYMENT_DECLINED']);

-- multiSearchAllPositions returns positions for each needle - useful for
-- highlighting / scoring.
SELECT ticket_id, multiSearchAllPositions(body, ['결제','환불','배송']) AS pos
FROM support_search.tickets_noidx
WHERE multiSearchAny(body, ['결제 실패','PAYMENT_DECLINED'])
LIMIT 5;

SELECT '=== 3.4 hasToken on un-indexed column (still scans) ===' AS section;
-- ----------------------------------------------------------------------------
-- 3.4 hasToken: tokenize on non-alphanum, check exact-token membership.
--     Without an index, this still scans — but the implementation is fast.
-- 3.4 hasToken: 영숫자 외 문자로 토큰화 후 일치 검사.
--     인덱스 없이는 여전히 풀스캔이지만 구현 자체는 빠름.
-- ----------------------------------------------------------------------------
SELECT count() AS hits
FROM support_search.tickets_noidx
WHERE hasToken(body, 'PAYMENT_DECLINED');

-- KEY OBSERVATION: try hasToken on a Korean substring. It will not match because
-- hasToken expects a whole token, and Korean tokens carry particles (조사).
-- 핵심 관찰: 한국어로 hasToken을 시도하면, 토큰에 조사가 붙어 있어 거의 매치되지 않음.
SELECT count() AS hits_korean_token
FROM support_search.tickets_noidx
WHERE hasToken(body, '결제');  -- almost always 0; tokens like "결제가", "결제는" don't equal "결제"

SELECT '=== 3.5 match() — regex search ===' AS section;
-- ----------------------------------------------------------------------------
-- 3.5 Regex: powerful, much slower. Use multiSearchAny first when possible.
-- 3.5 정규식: 강력하지만 훨씬 느림. 가능하면 multiSearchAny가 우선.
-- ----------------------------------------------------------------------------
-- Find Order IDs followed by 7-digit number anywhere in the body
SELECT count() AS hits
FROM support_search.tickets_noidx
WHERE match(body, 'Order ID:\\s*\\d{7}');

SELECT '=== 3.6 ILIKE — case-insensitive ===' AS section;
-- ----------------------------------------------------------------------------
-- 3.6 ILIKE for case-insensitive English; no-op for Korean (no case).
-- 3.6 ILIKE은 영어 대소문자 무시. 한국어는 대소문자 개념이 없어 무관.
-- ----------------------------------------------------------------------------
SELECT count() FROM support_search.tickets_noidx WHERE body ILIKE '%refund%';
SELECT count() FROM support_search.tickets_noidx WHERE body ILIKE '%REFUND%';

SELECT '=== 3.7 Phrase + filter combination ===' AS section;
-- ----------------------------------------------------------------------------
-- 3.7 Realistic agent query: "open critical billing tickets mentioning 결제".
-- 3.7 실제 상담사 쿼리: "결제 관련 critical/open 상태의 미해결 티켓"
-- ----------------------------------------------------------------------------
SELECT ticket_id, customer_id, priority, status, substring(subject, 1, 50) AS subj
FROM support_search.tickets_noidx
WHERE status IN ('open','in_progress')
  AND priority = 'critical'
  AND positionUTF8(body, '결제') > 0
ORDER BY created_at DESC
LIMIT 20;

SELECT '=== 3.8 Trace performance — show settings to read ===' AS section;
-- ----------------------------------------------------------------------------
-- 3.8 To see what each query actually did, enable trace logs in your client:
--     SET send_logs_level = 'trace';
-- Or check system.query_log after the fact:
-- 3.8 추적 활성화 또는 system.query_log 확인.
-- ----------------------------------------------------------------------------
SELECT
    query_duration_ms,
    formatReadableSize(memory_usage) AS mem,
    formatReadableQuantity(read_rows) AS rows_read,
    formatReadableSize(read_bytes) AS bytes_read,
    substring(query, 1, 80) AS query_head
FROM system.query_log
WHERE event_time > now() - INTERVAL 10 MINUTE
  AND query LIKE '%tickets_noidx%'
  AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 10;

-- Storage footprint of the baseline table (no index overhead at all)
-- 베이스라인 테이블의 저장 공간 (인덱스 오버헤드 전혀 없음)
SELECT
    formatReadableSize(sum(data_compressed_bytes))   AS compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio
FROM system.parts
WHERE database = 'support_search' AND table = 'tickets_noidx' AND active;
