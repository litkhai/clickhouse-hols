-- ============================================================================
-- kafka-partitioning-ingestion Step 6: measure all paths
-- 카프카 파티셔닝 인제스천 6단계: 전 경로 측정
-- ============================================================================
-- Run AFTER 05-produce.py, once every consumer has drained the topics:
--   docker compose exec -T clickhouse clickhouse-client --multiquery < 06-compare.sql
--
-- The 5 target tables:
--   engine_misaligned       PATH B (engine, tuned)   · hash topic   → baseline wide
--   engine_aligned          PATH B (engine, tuned)   · range topic  → pruning works
--   engine_default_aligned  PATH A (engine, default) · range topic  → locality DILUTED
--   connect_misaligned      PATH C (Connect sink)    · hash topic   → baseline wide
--   connect_aligned         PATH C (Connect sink)    · range topic  → pruning works
-- ============================================================================

-- 6.1 Ingestion complete? Every rows column should equal your ROWS (.env).
-- 6.1 인제스천 완료? 모든 rows가 .env의 ROWS와 같아야 함.
SELECT '--- 6.1 rows & parts per target (wait until rows == ROWS everywhere) ---';
SELECT table, count() AS parts, sum(rows) AS rows
FROM system.parts
WHERE active AND database = 'kpart'
  AND table IN ('engine_misaligned','engine_aligned','engine_default_aligned','connect_misaligned','connect_aligned')
GROUP BY table ORDER BY table;

-- 6.2 WHY — per-part customer_id span. Lower = better part pruning.
--     aligned paths → narrow & disjoint; misaligned & engine-default → full range.
-- 6.2 왜 — part별 customer_id 폭. 낮을수록 pruning이 잘 됨.
SELECT '--- 6.2 per-part customer_id span (avg / max across parts) ---';
SELECT 'engine_misaligned'      AS table, count() AS parts, round(avg(span)) AS avg_span, max(span) AS max_span FROM (SELECT _part, max(customer_id)-min(customer_id) AS span FROM kpart.engine_misaligned      GROUP BY _part)
UNION ALL
SELECT 'engine_aligned',             count(), round(avg(span)), max(span) FROM (SELECT _part, max(customer_id)-min(customer_id) AS span FROM kpart.engine_aligned             GROUP BY _part)
UNION ALL
SELECT 'engine_default_aligned',     count(), round(avg(span)), max(span) FROM (SELECT _part, max(customer_id)-min(customer_id) AS span FROM kpart.engine_default_aligned     GROUP BY _part)
UNION ALL
SELECT 'connect_misaligned',         count(), round(avg(span)), max(span) FROM (SELECT _part, max(customer_id)-min(customer_id) AS span FROM kpart.connect_misaligned         GROUP BY _part)
UNION ALL
SELECT 'connect_aligned',            count(), round(avg(span)), max(span) FROM (SELECT _part, max(customer_id)-min(customer_id) AS span FROM kpart.connect_aligned            GROUP BY _part)
ORDER BY 1;

-- 6.3 The planner's estimate for a point lookup. Columns: db·table·parts·rows·marks.
-- 6.3 point lookup에 대한 플래너 추정. 컬럼: db·table·parts·rows·marks.
SELECT '--- 6.3a EXPLAIN ESTIMATE: engine_misaligned ---';
EXPLAIN ESTIMATE SELECT count(), avg(val) FROM kpart.engine_misaligned WHERE customer_id = 4242;
SELECT '--- 6.3b EXPLAIN ESTIMATE: engine_aligned ---';
EXPLAIN ESTIMATE SELECT count(), avg(val) FROM kpart.engine_aligned WHERE customer_id = 4242;
SELECT '--- 6.3c EXPLAIN ESTIMATE: engine_default_aligned (diluted) ---';
EXPLAIN ESTIMATE SELECT count(), avg(val) FROM kpart.engine_default_aligned WHERE customer_id = 4242;
SELECT '--- 6.3d EXPLAIN ESTIMATE: connect_misaligned ---';
EXPLAIN ESTIMATE SELECT count(), avg(val) FROM kpart.connect_misaligned WHERE customer_id = 4242;
SELECT '--- 6.3e EXPLAIN ESTIMATE: connect_aligned ---';
EXPLAIN ESTIMATE SELECT count(), avg(val) FROM kpart.connect_aligned WHERE customer_id = 4242;

-- 6.4 Actual measured cost. Run the same lookup on each, flush logs, read back.
-- 6.4 실제 측정 비용. 동일 lookup을 각 테이블에 돌리고 로그 flush 후 읽어옴.
SELECT count(), avg(val) FROM kpart.engine_misaligned      WHERE customer_id = 4242 SETTINGS log_comment='kp_engine_misaligned';
SELECT count(), avg(val) FROM kpart.engine_aligned         WHERE customer_id = 4242 SETTINGS log_comment='kp_engine_aligned';
SELECT count(), avg(val) FROM kpart.engine_default_aligned WHERE customer_id = 4242 SETTINGS log_comment='kp_engine_default_aligned';
SELECT count(), avg(val) FROM kpart.connect_misaligned     WHERE customer_id = 4242 SETTINGS log_comment='kp_connect_misaligned';
SELECT count(), avg(val) FROM kpart.connect_aligned        WHERE customer_id = 4242 SETTINGS log_comment='kp_connect_aligned';

SYSTEM FLUSH LOGS;

SELECT '--- 6.4 measured read_rows / read_bytes / duration (latest probe per table) ---';
SELECT log_comment AS probe,
       read_rows,
       formatReadableSize(read_bytes) AS read_bytes,
       query_duration_ms
FROM system.query_log
WHERE type = 'QueryFinish' AND log_comment LIKE 'kp_%'
ORDER BY event_time DESC
LIMIT 1 BY log_comment;
