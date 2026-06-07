-- ============================================================================
-- Full-Text Search Lab · Step 4: Index Comparison
-- 풀텍스트 검색 실습 · Step 4: 인덱스 비교
-- ============================================================================
-- Run the SAME logical search against four tables and compare:
--   • elapsed time
--   • rows_read   (lower = better index pruning)
--   • bytes_read
--   • on-disk index size
--
-- Recommendation: run each block twice. Discard the first run — it warms the
-- page cache. Use the second run as the timing.
-- ============================================================================

SET use_query_cache = 0;
SET use_uncompressed_cache = 0;

-- ----------------------------------------------------------------------------
-- 4.0 Index storage footprint
-- 4.0 인덱스 저장 공간 비교
-- ----------------------------------------------------------------------------
SELECT
    table,
    name AS index_name,
    type,
    formatReadableSize(sum(data_compressed_bytes))   AS compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    sum(marks) AS marks
FROM system.data_skipping_indices
WHERE database = 'support_search'
GROUP BY table, name, type
ORDER BY table, name;

-- Total table size including all skip-index data
-- 모든 skip 인덱스를 포함한 전체 테이블 크기
SELECT
    table,
    formatReadableSize(sum(data_compressed_bytes))   AS data_compressed,
    formatReadableSize(sum(secondary_indices_compressed_bytes)) AS index_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_on_disk
FROM system.parts
WHERE database = 'support_search'
  AND active
  AND table LIKE 'tickets_%'
GROUP BY table
ORDER BY table;

-- ----------------------------------------------------------------------------
-- 4.1 English exact-token query: "PAYMENT_DECLINED"
-- 4.1 영어 정확 토큰 쿼리: "PAYMENT_DECLINED"
-- ----------------------------------------------------------------------------
-- This is the IDEAL case for tokenbf_v1 and text(asciiCJK): a single English
-- token that maps cleanly to a single index entry. Expect tokenbf and text
-- to prune most granules; ngrambf does fine too but has to OR several trigrams.
SELECT '4.1 PAYMENT_DECLINED — noidx' AS q, count() FROM support_search.tickets_noidx WHERE hasToken(body, 'PAYMENT_DECLINED');
SELECT '4.1 PAYMENT_DECLINED — token' AS q, count() FROM support_search.tickets_token WHERE hasToken(body, 'PAYMENT_DECLINED');
SELECT '4.1 PAYMENT_DECLINED — ngram' AS q, count() FROM support_search.tickets_ngram WHERE body LIKE '%PAYMENT_DECLINED%';
SELECT '4.1 PAYMENT_DECLINED — text'  AS q, count() FROM support_search.tickets_text  WHERE hasToken(body, 'PAYMENT_DECLINED');

-- ----------------------------------------------------------------------------
-- 4.2 Korean 2-char term: "결제"
-- 4.2 한국어 2글자 쿼리: "결제"
-- ----------------------------------------------------------------------------
-- This is where tokenbf_v1 fails dramatically: the token "결제" almost never
-- appears alone — corpus has "결제가", "결제는", "결제를", "결제 실패", etc.
-- So hasToken('결제') on tokenbf_v1 returns nearly zero, and using LIKE keeps
-- the index off-path entirely.
-- ngrambf trigrams help with LIKE pruning, text(asciiCJK) finds it as a token,
-- text(ngrams(2)) finds it via bigram lookup.
SELECT '4.2 결제 hasToken — noidx' AS q, count() FROM support_search.tickets_noidx WHERE hasToken(body, '결제');
SELECT '4.2 결제 hasToken — token' AS q, count() FROM support_search.tickets_token WHERE hasToken(body, '결제');  -- ~0
SELECT '4.2 결제 LIKE     — noidx' AS q, count() FROM support_search.tickets_noidx WHERE body LIKE '%결제%';
SELECT '4.2 결제 LIKE     — ngram' AS q, count() FROM support_search.tickets_ngram WHERE body LIKE '%결제%';
SELECT '4.2 결제 LIKE     — text'  AS q, count() FROM support_search.tickets_text  WHERE body LIKE '%결제%';
SELECT '4.2 결제 hasToken — text'  AS q, count() FROM support_search.tickets_text  WHERE hasToken(body, '결제');

-- ----------------------------------------------------------------------------
-- 4.3 Korean phrase with space: "결제 실패"
-- 4.3 공백 포함 한국어 구문: "결제 실패"
-- ----------------------------------------------------------------------------
-- Phrase queries are where text(asciiCJK) really shines via hasPhrase().
-- On the legacy bloom filters we have to fall back to LIKE.
SELECT '4.3 결제 실패 — noidx' AS q, count() FROM support_search.tickets_noidx WHERE body LIKE '%결제 실패%';
SELECT '4.3 결제 실패 — token' AS q, count() FROM support_search.tickets_token WHERE body LIKE '%결제 실패%';
SELECT '4.3 결제 실패 — ngram' AS q, count() FROM support_search.tickets_ngram WHERE body LIKE '%결제 실패%';
SELECT '4.3 결제 실패 — text(LIKE)'    AS q, count() FROM support_search.tickets_text WHERE body LIKE '%결제 실패%';
-- hasPhrase requires a text index with a tokenizer that segments by word.
-- 'hasPhrase'는 단어 단위로 토큰화된 text 인덱스가 있어야 작동.
SELECT '4.3 결제 실패 — text(hasPhrase)' AS q, count() FROM support_search.tickets_text WHERE hasPhrase(body, '결제 실패');

-- ----------------------------------------------------------------------------
-- 4.4 Multi-token OR: any of [결제, 환불, 배송]
-- 4.4 다중 토큰 OR: [결제, 환불, 배송] 중 하나라도 포함
-- ----------------------------------------------------------------------------
-- hasAnyTokens / searchAny is what an agent dashboard's "show me anything
-- about money or delivery" filter compiles to.
SELECT '4.4 OR(결제,환불,배송) — noidx' AS q, count() FROM support_search.tickets_noidx WHERE multiSearchAny(body, ['결제','환불','배송']);
SELECT '4.4 OR — ngram' AS q, count() FROM support_search.tickets_ngram WHERE multiSearchAny(body, ['결제','환불','배송']);
SELECT '4.4 OR — text(hasAnyTokens)' AS q, count() FROM support_search.tickets_text WHERE hasAnyTokens(body, ['결제','환불','배송']);

-- ----------------------------------------------------------------------------
-- 4.5 Multi-token AND: must contain ALL of [환불, 배송비]
-- 4.5 다중 토큰 AND: [환불, 배송비] 모두 포함
-- ----------------------------------------------------------------------------
SELECT '4.5 AND(환불,배송비) — noidx' AS q, count() FROM support_search.tickets_noidx WHERE body LIKE '%환불%' AND body LIKE '%배송비%';
SELECT '4.5 AND — ngram' AS q, count() FROM support_search.tickets_ngram WHERE body LIKE '%환불%' AND body LIKE '%배송비%';
SELECT '4.5 AND — text(hasAllTokens)' AS q, count() FROM support_search.tickets_text WHERE hasAllTokens(body, ['환불','배송비']);

-- ----------------------------------------------------------------------------
-- 4.6 Mixed Korean + English: "iPhone 결제"
-- 4.6 한+영 혼용: "iPhone 결제"
-- ----------------------------------------------------------------------------
-- This is the daily reality of Korean SaaS support. text(asciiCJK) is the
-- only index that tokenizes BOTH language scripts in one go.
SELECT '4.6 iPhone+결제 — noidx' AS q, count() FROM support_search.tickets_noidx WHERE body LIKE '%iPhone%' AND body LIKE '%결제%';
SELECT '4.6 iPhone+결제 — text'  AS q, count() FROM support_search.tickets_text  WHERE hasAllTokens(body, ['iPhone','결제']);

-- ----------------------------------------------------------------------------
-- 4.7 Force EXPLAIN to verify which granules each index actually skipped
-- 4.7 EXPLAIN으로 실제 어떤 인덱스가 granule을 건너뛰었는지 확인
-- ----------------------------------------------------------------------------
EXPLAIN indexes = 1
SELECT count() FROM support_search.tickets_text
WHERE hasAnyTokens(body, ['결제','환불']);

EXPLAIN indexes = 1
SELECT count() FROM support_search.tickets_ngram
WHERE body LIKE '%결제%';

EXPLAIN indexes = 1
SELECT count() FROM support_search.tickets_token
WHERE hasToken(body, 'PAYMENT_DECLINED');

-- ----------------------------------------------------------------------------
-- 4.8 Result summary from query_log
-- 4.8 query_log 기반 결과 요약
-- ----------------------------------------------------------------------------
-- After running everything above, pull a summary so you can compare.
-- 위 쿼리들을 모두 실행한 뒤 비교 요약을 추출.
SELECT
    extract(query, 'tickets_[a-z_]+') AS variant,
    extract(query, '''[^'']{0,40}''') AS needle_or_label,
    round(avg(query_duration_ms), 1) AS avg_ms,
    round(avg(read_rows) / 1000) AS avg_rows_read_k,
    formatReadableSize(avg(read_bytes)) AS avg_bytes_read
FROM system.query_log
WHERE event_time > now() - INTERVAL 30 MINUTE
  AND query LIKE '%support_search.tickets_%'
  AND type = 'QueryFinish'
  AND query_kind = 'Select'
GROUP BY variant, needle_or_label
ORDER BY variant, avg_ms DESC
LIMIT 50;
