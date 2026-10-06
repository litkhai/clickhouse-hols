-- Korean RAG keyword search — step 5: what each index costs
--
-- Steps 3 and 4 compared tokenizers on quality. This step looks at the bill:
--
--   1. how big each text index is, and how many tokens it holds
--   2. whether the index prunes granules for a real query (EXPLAIN)
--   3. how long a query takes at 30,000 rows, index vs scan
--
-- Everything here is the same eight indexes of step 2 on the same 300 chunks.

USE korean_rag;

-- Marker for section 3: only query_log rows from this run count, so running the
-- file twice on the same server does not mix the runs.
CREATE TEMPORARY TABLE krag05_start ENGINE = Memory AS SELECT now() AS t;

SELECT '════════ 1. Index size ════════' AS section;

-- data_compressed_bytes / data_uncompressed_bytes come from
-- system.data_skipping_indices. vs_body is the index's compressed size divided by
-- the compressed size of the `body` column it indexes (the original text).
-- distinct_tokens and avg_tokens_per_chunk come from chunk_tokens (step 3): the
-- vocabulary of the tokenizer and how many tokens it makes per chunk.
-- At 300 rows the byte counts are small and header overhead is a large part of
-- them, so compare the ratios between tokenizers rather than the absolute sizes.
WITH
    (
        SELECT sum(data_compressed_bytes)
        FROM system.columns
        WHERE database = 'korean_rag' AND table = 'chunks' AND name = 'body'
    ) AS body_compressed
SELECT
    t.tok AS tok,
    i.data_compressed_bytes AS index_compressed,
    i.data_uncompressed_bytes AS index_uncompressed,
    round(i.data_compressed_bytes / body_compressed, 2) AS vs_body,
    s.distinct_tokens AS distinct_tokens,
    round(s.avg_tokens, 1) AS avg_tokens_per_chunk
FROM tokenizers AS t
INNER JOIN system.data_skipping_indices AS i
    ON i.name = t.index_name AND i.database = 'korean_rag' AND i.table = 'chunks'
INNER JOIN
(
    SELECT tok, length(groupUniqArrayArray(toks)) AS distinct_tokens, avg(length(toks)) AS avg_tokens
    FROM chunk_tokens
    GROUP BY tok
) AS s ON s.tok = t.tok
ORDER BY t.ord
FORMAT TSVWithNames;

SELECT '════════ 2. Granule pruning ════════' AS section;

-- chunks has index_granularity = 8, so its 300 rows are 38 granules. For each
-- tokenizer, EXPLAIN indexes = 1 reports how many of them the text index lets
-- through ("Granules: kept/total"); the fewer, the less data a query reads.
-- Only the index's own lines are kept: its name and its Granules line.
-- An empty name means the index did not take part in the plan.
--
-- The EXPLAINs use sum(id): a bare count() is answered from the index alone
-- ("Trivial count from text index") and the plan then has no Granules line.
--
-- (a) a literal needle, hasAllTokens(col, '법인카드 분실'). A String needle is
--     tokenized by the index's tokenizer. For kiwi the needle is an array, the
--     tokens Kiwi gives for that phrase: 법인 / 카드 / 분실.
SELECT tok, 'hasAllTokens: 법인카드 분실' AS needle, trim(lines[p]) AS index_line,
       trim(arrayFirst(l -> position(l, 'Granules:') > 0, arraySlice(lines, if(p = 0, 1, p)))) AS granules
FROM
(
    SELECT ord, tok, lines, arrayFirstIndex(l -> position(l, 'Name:') > 0, lines) AS p
    FROM
    (
        SELECT 1 AS ord, 'splitByNonAlpha' AS tok, groupArray(explain) AS lines
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAllTokens(b_nonalpha, '법인카드 분실'))
        UNION ALL
        SELECT 2, 'asciiCJK', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAllTokens(b_cjk, '법인카드 분실'))
        UNION ALL
        SELECT 3, 'ngrams(2)', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAllTokens(b_ng2, '법인카드 분실'))
        UNION ALL
        SELECT 4, 'ngrams(3)', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAllTokens(b_ng3, '법인카드 분실'))
        UNION ALL
        SELECT 5, 'sparseGrams', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAllTokens(b_sparse, '법인카드 분실'))
        UNION ALL
        SELECT 6, 'icu(ko)', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAllTokens(b_icu, '법인카드 분실'))
        UNION ALL
        SELECT 7, 'splitByRegexp', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAllTokens(b_regexp, '법인카드 분실'))
        UNION ALL
        SELECT 8, 'kiwi', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAllTokens(morphemes, ['법인', '카드', '분실']))
    )
)
ORDER BY ord
FORMAT TSVWithNames;

-- (b) a whole question as the needle, hasAnyTokens(col, <scalar subquery>): the
--     first particle question, qid 1. For kiwi the needle is that question's
--     morphemes. A long needle makes many tokens and `any` keeps a granule if
--     it holds one of them, so expect less pruning than in (a).
SELECT tok, 'hasAnyTokens: question qid 1' AS needle, trim(lines[p]) AS index_line,
       trim(arrayFirst(l -> position(l, 'Granules:') > 0, arraySlice(lines, if(p = 0, 1, p)))) AS granules
FROM
(
    SELECT ord, tok, lines, arrayFirstIndex(l -> position(l, 'Name:') > 0, lines) AS p
    FROM
    (
        SELECT 1 AS ord, 'splitByNonAlpha' AS tok, groupArray(explain) AS lines
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAnyTokens(b_nonalpha, (SELECT question FROM queries WHERE qid = 1)))
        UNION ALL
        SELECT 2, 'asciiCJK', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAnyTokens(b_cjk, (SELECT question FROM queries WHERE qid = 1)))
        UNION ALL
        SELECT 3, 'ngrams(2)', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAnyTokens(b_ng2, (SELECT question FROM queries WHERE qid = 1)))
        UNION ALL
        SELECT 4, 'ngrams(3)', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAnyTokens(b_ng3, (SELECT question FROM queries WHERE qid = 1)))
        UNION ALL
        SELECT 5, 'sparseGrams', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAnyTokens(b_sparse, (SELECT question FROM queries WHERE qid = 1)))
        UNION ALL
        SELECT 6, 'icu(ko)', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAnyTokens(b_icu, (SELECT question FROM queries WHERE qid = 1)))
        UNION ALL
        SELECT 7, 'splitByRegexp', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAnyTokens(b_regexp, (SELECT question FROM queries WHERE qid = 1)))
        UNION ALL
        SELECT 8, 'kiwi', groupArray(explain)
        FROM (EXPLAIN indexes = 1 SELECT sum(id) FROM chunks WHERE hasAnyTokens(morphemes, (SELECT morphemes FROM queries WHERE qid = 1)))
    )
)
ORDER BY ord
FORMAT TSVWithNames;

SELECT '════════ 3. Latency at 30,000 rows ════════' AS section;

-- chunks_x100 is `chunks` repeated 100 times (id = copy * 1000 + id), with the
-- same eight indexes. The text repeats, so the dictionaries do not grow: this
-- measures how much a lookup reads from the posting lists, not what a bigger
-- vocabulary would cost.
DROP TABLE IF EXISTS chunks_x100;
CREATE TABLE chunks_x100 AS chunks;

INSERT INTO chunks_x100 (id, doc, body, morphemes)
SELECT n.number * 1000 + c.id, c.doc, c.body, c.morphemes
FROM chunks AS c
CROSS JOIN numbers(100) AS n;

SELECT count() AS rows, uniqExact(body) AS distinct_bodies FROM chunks_x100 FORMAT TSVWithNames;

-- The query is `SELECT sum(id) ... WHERE hasAllTokens(col, '법인카드 분실')`,
-- run five times per tokenizer with the index (log_comment krag05:<tok>:index).
-- It uses sum(id) and not count() because count() is answered from the index
-- directly and would hide the read.
-- Then once per tokenizer with the index switched off (krag05:<tok>:scan), and
-- a LIKE baseline on the raw text (krag05:like:scan).
-- Results go to FORMAT Null; timings come from system.query_log below.

SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_nonalpha, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByNonAlpha:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_nonalpha, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByNonAlpha:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_nonalpha, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByNonAlpha:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_nonalpha, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByNonAlpha:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_nonalpha, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByNonAlpha:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_nonalpha, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0, log_comment = 'krag05:splitByNonAlpha:scan' FORMAT Null;

SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_cjk, '법인카드 분실') SETTINGS log_comment = 'krag05:asciiCJK:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_cjk, '법인카드 분실') SETTINGS log_comment = 'krag05:asciiCJK:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_cjk, '법인카드 분실') SETTINGS log_comment = 'krag05:asciiCJK:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_cjk, '법인카드 분실') SETTINGS log_comment = 'krag05:asciiCJK:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_cjk, '법인카드 분실') SETTINGS log_comment = 'krag05:asciiCJK:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_cjk, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0, log_comment = 'krag05:asciiCJK:scan' FORMAT Null;

SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng2, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(2):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng2, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(2):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng2, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(2):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng2, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(2):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng2, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(2):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng2, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0, log_comment = 'krag05:ngrams(2):scan' FORMAT Null;

SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng3, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(3):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng3, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(3):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng3, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(3):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng3, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(3):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng3, '법인카드 분실') SETTINGS log_comment = 'krag05:ngrams(3):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng3, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0, log_comment = 'krag05:ngrams(3):scan' FORMAT Null;

SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_sparse, '법인카드 분실') SETTINGS log_comment = 'krag05:sparseGrams:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_sparse, '법인카드 분실') SETTINGS log_comment = 'krag05:sparseGrams:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_sparse, '법인카드 분실') SETTINGS log_comment = 'krag05:sparseGrams:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_sparse, '법인카드 분실') SETTINGS log_comment = 'krag05:sparseGrams:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_sparse, '법인카드 분실') SETTINGS log_comment = 'krag05:sparseGrams:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_sparse, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0, log_comment = 'krag05:sparseGrams:scan' FORMAT Null;

SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_icu, '법인카드 분실') SETTINGS log_comment = 'krag05:icu(ko):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_icu, '법인카드 분실') SETTINGS log_comment = 'krag05:icu(ko):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_icu, '법인카드 분실') SETTINGS log_comment = 'krag05:icu(ko):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_icu, '법인카드 분실') SETTINGS log_comment = 'krag05:icu(ko):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_icu, '법인카드 분실') SETTINGS log_comment = 'krag05:icu(ko):index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_icu, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0, log_comment = 'krag05:icu(ko):scan' FORMAT Null;

SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_regexp, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByRegexp:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_regexp, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByRegexp:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_regexp, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByRegexp:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_regexp, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByRegexp:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_regexp, '법인카드 분실') SETTINGS log_comment = 'krag05:splitByRegexp:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_regexp, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0, log_comment = 'krag05:splitByRegexp:scan' FORMAT Null;

-- kiwi: the needle is the array Kiwi gives for the phrase.
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(morphemes, ['법인', '카드', '분실']) SETTINGS log_comment = 'krag05:kiwi:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(morphemes, ['법인', '카드', '분실']) SETTINGS log_comment = 'krag05:kiwi:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(morphemes, ['법인', '카드', '분실']) SETTINGS log_comment = 'krag05:kiwi:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(morphemes, ['법인', '카드', '분실']) SETTINGS log_comment = 'krag05:kiwi:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(morphemes, ['법인', '카드', '분실']) SETTINGS log_comment = 'krag05:kiwi:index' FORMAT Null;
SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(morphemes, ['법인', '카드', '분실']) SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0, log_comment = 'krag05:kiwi:scan' FORMAT Null;

-- baseline: no tokenizer at all, substring match on the raw text.
SELECT sum(id) FROM chunks_x100 WHERE body LIKE '%법인카드%' AND body LIKE '%분실%' SETTINGS log_comment = 'krag05:like:scan' FORMAT Null;

-- Do the index and the scan return the same rows? The timings above compare
-- two ways of answering one question, so first make sure it is one question.
SELECT tok, via_index, via_scan, via_index = via_scan AS same
FROM
(
    SELECT 1 AS ord, 'splitByNonAlpha' AS tok,
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_nonalpha, '법인카드 분실')) AS via_index,
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_nonalpha, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0) AS via_scan
    UNION ALL
    SELECT 2, 'asciiCJK',
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_cjk, '법인카드 분실')),
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_cjk, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0)
    UNION ALL
    SELECT 3, 'ngrams(2)',
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng2, '법인카드 분실')),
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng2, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0)
    UNION ALL
    SELECT 4, 'ngrams(3)',
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng3, '법인카드 분실')),
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_ng3, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0)
    UNION ALL
    SELECT 5, 'sparseGrams',
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_sparse, '법인카드 분실')),
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_sparse, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0)
    UNION ALL
    SELECT 6, 'icu(ko)',
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_icu, '법인카드 분실')),
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_icu, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0)
    UNION ALL
    SELECT 7, 'splitByRegexp',
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_regexp, '법인카드 분실')),
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(b_regexp, '법인카드 분실') SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0)
    UNION ALL
    SELECT 8, 'kiwi',
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(morphemes, ['법인', '카드', '분실'])),
           (SELECT sum(id) FROM chunks_x100 WHERE hasAllTokens(morphemes, ['법인', '카드', '분실']) SETTINGS use_skip_indexes = 0, query_plan_direct_read_from_text_index = 0)
)
ORDER BY ord
FORMAT TSVWithNames;

SYSTEM FLUSH LOGS;

-- Median over the runs of each label. `index` has 5 runs, `scan` and `like` one.
-- read_rows is the number of rows the query read from the table (of 30,000):
-- start there, it is stable; the milliseconds are a laptop container's and move
-- from run to run.
SELECT
    splitByChar(':', log_comment)[2] AS tok,
    splitByChar(':', log_comment)[3] AS mode,
    quantileExact(0.5)(query_duration_ms) AS median_ms,
    quantileExact(0.5)(read_rows) AS median_read_rows,
    count() AS runs
FROM system.query_log
WHERE type = 'QueryFinish'
  AND log_comment LIKE 'krag05:%'
  AND event_time >= (SELECT t FROM krag05_start)
GROUP BY log_comment, tok, mode
ORDER BY indexOf(['splitByNonAlpha', 'asciiCJK', 'ngrams(2)', 'ngrams(3)', 'sparseGrams', 'icu(ko)', 'splitByRegexp', 'kiwi', 'like'], tok), mode = 'scan'
FORMAT TSVWithNames;
