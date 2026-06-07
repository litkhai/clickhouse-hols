-- ============================================================================
-- Full-Text Search Lab · Step 7: Index Management & Monitoring
-- 풀텍스트 검색 실습 · Step 7: 인덱스 관리 및 모니터링
-- ============================================================================
-- Operational tasks: rebuild indexes, monitor index health, drop/add at
-- runtime, observe how INSERTs affect index size, and clean up.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 7.1 List every skip index in the database with size and granularity
-- 7.1 데이터베이스의 모든 skip 인덱스 목록 + 크기/granularity
-- ----------------------------------------------------------------------------
SELECT
    database,
    table,
    name AS index_name,
    type_full,
    granularity,
    expr
FROM system.data_skipping_indices
WHERE database = 'support_search'
ORDER BY table, name;

-- Per-index disk footprint (compressed and uncompressed)
-- 인덱스별 디스크 사용량
SELECT
    table,
    name,
    formatReadableSize(sum(data_compressed_bytes))   AS compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    sum(marks) AS marks
FROM system.data_skipping_indices
WHERE database = 'support_search'
GROUP BY table, name
ORDER BY sum(data_compressed_bytes) DESC;

-- ----------------------------------------------------------------------------
-- 7.2 Verify which granules each index is actually skipping
-- 7.2 각 인덱스가 실제로 어떤 granule을 건너뛰는지 확인
-- ----------------------------------------------------------------------------
-- A skip index that never prunes anything is dead weight. Run a few
-- production-shaped queries and check.
-- 한 번도 prune하지 않는 인덱스는 비용만 발생. 대표 쿼리로 검증.
EXPLAIN indexes = 1
SELECT count() FROM support_search.tickets_text WHERE hasAnyTokens(body, ['결제','환불','배송']);

EXPLAIN indexes = 1
SELECT count() FROM support_search.tickets_ngram WHERE body LIKE '%결제 실패%';

EXPLAIN indexes = 1
SELECT count() FROM support_search.tickets_token WHERE hasToken(body, 'PAYMENT_DECLINED');

-- ----------------------------------------------------------------------------
-- 7.3 Rebuild / drop / add an index at runtime (no full rewrite needed)
-- 7.3 런타임 인덱스 재구축 / 삭제 / 추가
-- ----------------------------------------------------------------------------
-- Drop an index that's not paying for itself, e.g. the ngrams(2) one on
-- tickets_text (it's mainly there for the lab; in prod you'd usually keep
-- only asciiCJK).
-- 효과 없는 인덱스를 런타임에 제거.
ALTER TABLE support_search.tickets_text DROP INDEX IF EXISTS idx_body_gram2;

-- Add it back (or change its parameters). Default is "materialize lazily
-- on the next MERGE", so issue MATERIALIZE INDEX to force backfill now.
-- 기본은 다음 머지 때 채워지지만, 즉시 백필하려면 MATERIALIZE INDEX.
ALTER TABLE support_search.tickets_text
    ADD INDEX idx_body_gram2 body TYPE text(tokenizer = 'ngrams', ngram_size = 2) GRANULARITY 1;

ALTER TABLE support_search.tickets_text
    MATERIALIZE INDEX idx_body_gram2;

-- Watch the backfill complete
-- 백필 진행 확인
SELECT
    command,
    is_done,
    create_time,
    parts_to_do_names
FROM system.mutations
WHERE database = 'support_search'
  AND table = 'tickets_text'
ORDER BY create_time DESC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- 7.4 Compare index effectiveness — which one earns its disk usage?
-- 7.4 인덱스 효율 비교 — 어떤 인덱스가 디스크 비용 대비 값을 하나
-- ----------------------------------------------------------------------------
-- A useful metric per index: (compressed_bytes / queries_that_used_it).
-- ClickHouse doesn't track per-index hit counts directly, but the EXPLAIN
-- indexes output and system.query_log with `EXPLAIN PIPELINE` give insight.
-- For day-to-day ops, this query gives a rough ranking by storage cost:
-- ----------------------------------------------------------------------------
SELECT
    table,
    name,
    type_full,
    formatReadableSize(sum(data_compressed_bytes)) AS compressed,
    -- Cost as % of table data size
    round(
        sum(data_compressed_bytes) * 100.0
        / (SELECT sum(data_compressed_bytes) FROM system.parts WHERE database = 'support_search' AND table = dsi.table AND active),
        2
    ) AS pct_of_table
FROM system.data_skipping_indices dsi
WHERE database = 'support_search'
GROUP BY table, name, type_full
ORDER BY pct_of_table DESC;

-- ----------------------------------------------------------------------------
-- 7.5 Insert performance impact
-- 7.5 INSERT 성능 영향
-- ----------------------------------------------------------------------------
-- Index builds happen during merges. To measure write-time cost cleanly,
-- insert the same 10k rows into all four tables and compare.
-- 인덱스 구축은 merge 시점에 발생. 동일 10k행을 4 테이블에 적재해 비교.
TRUNCATE TABLE IF EXISTS support_search.tickets_noidx_perf;
CREATE TABLE IF NOT EXISTS support_search.tickets_noidx_perf AS support_search.tickets_noidx;

-- (Add similar empty clones in your own test if you want a clean before/after.)
-- Quick comparison from query_log filtered by query_kind='Insert':
SELECT
    extract(query, 'tickets_[a-z_]+') AS target_table,
    count() AS insert_count,
    round(avg(query_duration_ms), 1) AS avg_ms,
    formatReadableQuantity(avg(written_rows)) AS avg_rows
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
  AND query_kind = 'Insert'
  AND query LIKE '%support_search.tickets_%'
  AND type = 'QueryFinish'
GROUP BY target_table
ORDER BY avg_ms DESC;

-- ----------------------------------------------------------------------------
-- 7.6 Merge / part stats — large text indexes may slow merges
-- 7.6 머지 / part 통계 — 큰 text 인덱스는 merge 속도를 늦출 수 있음
-- ----------------------------------------------------------------------------
SELECT
    table,
    count() AS parts,
    formatReadableSize(sum(bytes_on_disk)) AS total_size,
    formatReadableSize(sum(secondary_indices_compressed_bytes)) AS index_size,
    round(sum(secondary_indices_compressed_bytes) * 100.0 / sum(bytes_on_disk), 2) AS index_pct_of_part
FROM system.parts
WHERE database = 'support_search' AND active
GROUP BY table
ORDER BY index_size DESC;

-- ----------------------------------------------------------------------------
-- 7.7 Query log slice — what your users are actually searching
-- 7.7 query_log 분석 — 사용자가 실제로 무엇을 검색하는가
-- ----------------------------------------------------------------------------
-- Extract the search needles from query text so the product team can see
-- which terms drive the most expensive queries.
-- 쿼리 텍스트에서 검색어 추출 → 가장 비싼 쿼리 패턴을 제품팀에 공유.
SELECT
    extract(query, '''([^'']{2,30})''') AS needle,
    count() AS query_count,
    round(avg(query_duration_ms), 1) AS avg_ms,
    round(quantile(0.95)(query_duration_ms), 1) AS p95_ms,
    formatReadableSize(avg(read_bytes)) AS avg_bytes_read
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 DAY
  AND query LIKE '%support_search.tickets_%'
  AND type = 'QueryFinish'
  AND needle != ''
GROUP BY needle
HAVING query_count > 1
ORDER BY p95_ms DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- 7.8 Cleanup
-- 7.8 정리
-- ----------------------------------------------------------------------------
-- Don't accidentally drop in shared Cloud! Run only when finished.
-- 공용 Cloud에서 실수로 실행하지 않도록 주의.
--
-- DROP DATABASE IF EXISTS support_search;
SELECT 'To drop: DROP DATABASE IF EXISTS support_search;' AS cleanup_hint;
