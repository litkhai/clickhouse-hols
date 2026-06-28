-- ============================================================================
-- kafka-partitioning-ingestion Step 0: Deterministic SQL proof (no Kafka)
-- 카프카 파티셔닝 인제스천 0단계: 결정적 SQL 증명 (카프카 불필요)
-- ============================================================================
-- This file isolates the ONE variable that Kafka partitioning ultimately
-- controls: the *insertion order* of rows into ClickHouse. Same data, same
-- ORDER BY, same index_granularity — only the order each batch (= part) carries
-- differs. The EXPLAIN ESTIMATE numbers here are deterministic and reproduce
-- identically on any machine; the Kafka pipeline (steps 01-06) then shows the
-- same effect emerging end-to-end from real range vs hash partitioning.
--
-- 이 파일은 카프카 파티셔닝이 궁극적으로 좌우하는 단 하나의 변수, 즉 ClickHouse로의
-- *삽입 순서*만 분리한다. 동일 데이터·동일 ORDER BY·동일 index_granularity이고,
-- 각 배치(=part)가 운반하는 순서만 다르다. 여기 EXPLAIN ESTIMATE 수치는 결정적이라
-- 어디서 돌려도 동일하게 재현된다. 이후 카프카 파이프라인(01-06)이 실제 range vs hash
-- 파티셔닝에서 같은 효과가 end-to-end로 나타남을 보여준다.
--
-- Run against the dockerized server (recommended, matches the rest of the lab):
--   docker compose exec -T clickhouse clickhouse-client --multiquery < 00-explain-estimate.sql
-- Or fully standalone, no Docker at all:
--   ./clickhouse local --multiquery < 00-explain-estimate.sql
-- ============================================================================

CREATE DATABASE IF NOT EXISTS kpart;

DROP TABLE IF EXISTS kpart.sql_misaligned;
DROP TABLE IF EXISTS kpart.sql_aligned;

-- Two tables: IDENTICAL ORDER BY, IDENTICAL granularity.
-- 두 테이블: 동일한 ORDER BY, 동일한 granularity.
CREATE TABLE kpart.sql_misaligned (customer_id UInt32, ts DateTime, val UInt32)
ENGINE = MergeTree ORDER BY (customer_id, ts)
SETTINGS index_granularity = 8192;

CREATE TABLE kpart.sql_aligned (customer_id UInt32, ts DateTime, val UInt32)
ENGINE = MergeTree ORDER BY (customer_id, ts)
SETTINGS index_granularity = 8192;

-- Stop background merges so part-level differences stay observable.
-- 백그라운드 머지를 멈춰 part 단위 차이를 관찰 가능하게 둔다.
SYSTEM STOP MERGES kpart.sql_misaligned;
SYSTEM STOP MERGES kpart.sql_aligned;

-- 10M rows · 10,000 customers · 20 batches (= 20 parts).
-- [MISALIGNED] every batch pulls customer_id randomly from the FULL [0,9999]
-- range — the hash-partitioning analogue (many keys mixed into one partition).
-- [비정렬] 각 배치가 customer_id를 [0,9999] 전 범위에서 무작위 추출 — hash 파티셔닝
-- 모사(한 파티션에 여러 키가 섞임).
INSERT INTO kpart.sql_misaligned
SELECT (rand() % 10000) AS customer_id,
       now() - (rand() % 2592000) AS ts,
       rand() AS val
FROM numbers(10000000)
SETTINGS max_insert_block_size = 500000, min_insert_block_size_rows = 500000;

-- [ALIGNED] batch i carries a CONTIGUOUS customer range — the range/custom
-- partitioning analogue (each partition owns a disjoint key interval).
-- [정렬] 배치 i가 연속 customer 구간만 운반 — range/custom 파티셔닝 모사(각 파티션이
-- 서로 겹치지 않는 키 구간을 소유).
INSERT INTO kpart.sql_aligned
SELECT intDiv(number, 1000) AS customer_id,          -- 0..9999 ascending
       now() - (rand() % 2592000) AS ts,
       rand() AS val
FROM numbers(10000000)
SETTINGS max_insert_block_size = 500000, min_insert_block_size_rows = 500000;

-- Part counts (should be ~20 each, merges are stopped).
-- part 수 확인 (머지 정지 상태라 각 ~20개).
SELECT '--- part counts ---';
SELECT table, count() AS parts, sum(rows) AS rows
FROM system.parts WHERE active AND database = 'kpart' AND table LIKE 'sql_%'
GROUP BY table ORDER BY table;

-- The core metric: parts · rows · marks ClickHouse expects to read.
-- Output columns are: database · table · parts · rows · marks.
-- 핵심 지표: 읽을 part · 행 · 마크 추정. 컬럼 순서는 database·table·parts·rows·marks.
SELECT '--- EXPLAIN ESTIMATE: misaligned (expect ~20 parts / ~163840 rows / ~20 marks) ---';
EXPLAIN ESTIMATE SELECT count(), avg(val) FROM kpart.sql_misaligned WHERE customer_id = 4242;

SELECT '--- EXPLAIN ESTIMATE: aligned (expect 1 part / 8192 rows / 1 mark) ---';
EXPLAIN ESTIMATE SELECT count(), avg(val) FROM kpart.sql_aligned WHERE customer_id = 4242;

-- Optional: see the exact granule ranges the index keeps/drops per part.
-- 옵션: 인덱스가 part별로 유지/제거하는 granule 범위를 직접 확인.
SELECT '--- EXPLAIN indexes=1: aligned ---';
EXPLAIN indexes = 1 SELECT count(), avg(val) FROM kpart.sql_aligned WHERE customer_id = 4242;
