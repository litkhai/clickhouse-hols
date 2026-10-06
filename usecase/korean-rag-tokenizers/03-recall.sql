-- Korean RAG keyword search — step 3: which chunks does each tokenizer find?
--
-- Filtering only, no ranking (that is step 4). For every question and every
-- tokenizer we ask two things of the chunks:
--
--   any  the chunk shares at least one token with the question   (hasAny)
--   all  the chunk contains every token of the question          (hasAll)
--
-- and compare the returned set R with the hand-labelled relevant set G in
-- `queries.relevant`:
--
--   recall    = |R ∩ G| / |G|      did we find what we should have?
--   precision = |R ∩ G| / |R|      how much else came with it? (0 when R is empty)
--
-- Both are averaged over questions (macro average).
--
-- Why token arrays instead of calling hasAnyTokens in a loop: the needle of
-- hasAnyTokens / hasAllTokens must be a constant, so it cannot come from a join
-- (step 1, section 4). So the tokens of every chunk and every question are
-- computed once, stored as arrays, and compared with hasAny / hasAll. Section 3
-- then checks that this agrees with what the text indexes themselves return.

USE korean_rag;

SELECT '════════ 1. Token tables ════════' AS section;

-- chunk_tokens / query_tokens are long-form: one row per tokenizer x chunk (or
-- question). The first seven tokenizers run on lower(text); `kiwi` is the
-- morphemes column. On the question side tokens are de-duplicated, because a
-- repeated word in a question should not count twice.
-- Steps 4 and 5 reuse both tables.

DROP TABLE IF EXISTS chunk_tokens;
CREATE TABLE chunk_tokens
(
    tok   LowCardinality(String),
    id    UInt32,
    toks  Array(String)
)
ENGINE = MergeTree ORDER BY (tok, id);

DROP TABLE IF EXISTS query_tokens;
CREATE TABLE query_tokens
(
    tok   LowCardinality(String),
    qid   UInt16,
    toks  Array(String)
)
ENGINE = MergeTree ORDER BY (tok, qid);

-- The pattern is the one in the splitByRegexp index of step 2 (see step 1 for
-- what it does).
INSERT INTO chunk_tokens
WITH '([\\p{L}\\p{N}]+?)(?:은|는|이|가|을|를|에서|에게|에|의|로|으로|와|과|도|만)?(?:[^\\p{L}\\p{N}]|$)' AS re
SELECT t.1 AS tok, id, t.2 AS toks
FROM
(
    SELECT
        id,
        lower(body) AS lb,
        arrayJoin([
            ('splitByNonAlpha', tokens(lb, 'splitByNonAlpha')),
            ('asciiCJK',        tokens(lb, 'asciiCJK')),
            ('ngrams(2)',       tokens(lb, 'ngrams', 2)),
            ('ngrams(3)',       tokens(lb, 'ngrams', 3)),
            ('sparseGrams',     tokens(lb, 'sparseGrams')),
            ('icu(ko)',         tokens(lb, 'icu', 'ko')),
            ('splitByRegexp',   tokens(lb, 'splitByRegexp', re, true)),
            ('kiwi',            morphemes)
        ]) AS t
    FROM chunks
);

INSERT INTO query_tokens
WITH '([\\p{L}\\p{N}]+?)(?:은|는|이|가|을|를|에서|에게|에|의|로|으로|와|과|도|만)?(?:[^\\p{L}\\p{N}]|$)' AS re
SELECT t.1 AS tok, qid, arrayDistinct(t.2) AS toks
FROM
(
    SELECT
        qid,
        lower(question) AS lq,
        tokens(lq, 'sparseGrams') AS sg,
        arrayJoin([
            ('splitByNonAlpha', tokens(lq, 'splitByNonAlpha')),
            ('asciiCJK',        tokens(lq, 'asciiCJK')),
            ('ngrams(2)',       tokens(lq, 'ngrams', 2)),
            ('ngrams(3)',       tokens(lq, 'ngrams', 3)),
            -- Not tokens() as is: a String needle goes through compactTokens()
            -- first, and for sparseGrams that drops every gram contained in a
            -- longer one (src/Interpreters/ITokenizer.cpp, applied in
            -- src/Functions/hasAnyAllTokens.cpp for hasAny and hasAll alike,
            -- v26.9.11.2-stable). The filter below does the same, so the arrays
            -- see the needle the index sees. Section 3 checks it.
            ('sparseGrams',     arrayFilter(g -> NOT arrayExists(h -> length(h) > length(g) AND position(h, g) > 0, sg), sg)),
            ('icu(ko)',         tokens(lq, 'icu', 'ko')),
            ('splitByRegexp',   tokens(lq, 'splitByRegexp', re, true)),
            ('kiwi',            morphemes)
        ]) AS t
    FROM queries
);

-- One question through all eight tokenizers (qid 1, a particle case). Compare
-- what each one makes of the noun 출장비를: whole with its particle, split into
-- syllables or n-grams, or reduced to a bare stem. The sparseGrams row is what is
-- left after compaction: the longest grams, which almost no chunk contains.
SELECT q.tok, q.toks
FROM query_tokens AS q
INNER JOIN tokenizers AS t ON t.tok = q.tok
WHERE q.qid = 1
ORDER BY t.ord
FORMAT TSVWithNames;

-- Rows per tokenizer, and how many questions produced no token at all with it.
SELECT
    t.tok AS tok,
    (SELECT count() FROM chunk_tokens WHERE tok = t.tok)                AS chunk_rows,
    (SELECT count() FROM query_tokens WHERE tok = t.tok)                AS query_rows,
    (SELECT countIf(empty(toks)) FROM query_tokens WHERE tok = t.tok)   AS queries_with_no_token
FROM tokenizers AS t
ORDER BY t.ord
FORMAT TSVWithNames;

SELECT '════════ 2. Matching: any and all ════════' AS section;

-- recall_eval keeps one row per tokenizer x fn x question:
--   n_relevant  |G|, the hand-labelled chunks
--   n_returned  |R|, the chunks the filter returned
--   n_hit       |R ∩ G|
-- A question with no tokens matches nothing under `all` (hasAll of an empty
-- array is true for every chunk, which is not what a search should do).

DROP TABLE IF EXISTS recall_eval;
CREATE TABLE recall_eval
(
    tok         LowCardinality(String),
    fn          LowCardinality(String),
    qid         UInt16,
    fcase       LowCardinality(String),
    n_relevant  UInt8,
    n_returned  UInt32,
    n_hit       UInt32
)
ENGINE = MergeTree ORDER BY (tok, fn, qid);

INSERT INTO recall_eval
SELECT tok, fn, qid, fcase, length(relevant) AS n_relevant, n_returned, n_hit
FROM
(
    SELECT
        q.tok AS tok,
        q.qid AS qid,
        qs.fcase AS fcase,
        qs.relevant AS relevant,
        countIf(hasAny(c.toks, q.toks))                                               AS any_returned,
        countIf(hasAny(c.toks, q.toks) AND has(qs.relevant, c.id))                    AS any_hit,
        countIf(notEmpty(q.toks) AND hasAll(c.toks, q.toks))                          AS all_returned,
        countIf(notEmpty(q.toks) AND hasAll(c.toks, q.toks) AND has(qs.relevant, c.id)) AS all_hit
    FROM query_tokens AS q
    INNER JOIN chunk_tokens AS c ON c.tok = q.tok
    INNER JOIN queries AS qs ON qs.qid = q.qid
    GROUP BY q.tok, q.qid, qs.fcase, qs.relevant
)
ARRAY JOIN
    ['any', 'all'] AS fn,
    [any_returned, all_returned] AS n_returned,
    [any_hit, all_hit] AS n_hit;

SELECT '════════ 3. Positive control: do the arrays agree with the index? ════════' AS section;

-- Everything below trusts the token arrays, so first check them against the
-- real thing. For three questions (the first particle, mixed and short ones) and
-- all eight tokenizers we count the chunks the *text index* returns and compare
-- with |R| from recall_eval: 3 x 8 x 2 = 48 rows.
--
-- The index count is `count() ... WHERE hasAnyTokens(...)`. A WHERE is what lets
-- the index answer; a countIf in the select list would only evaluate the function.
-- The needle is a scalar subquery (the only way to take it from a table). The
-- String needle is tokenized by the index's own tokenizer, lowercased by its
-- preprocessor; the kiwi needle is the Array(String) of morphemes, used as is.
--
-- If a row says ok = 0, stop: the recall numbers further down are not about the
-- index. The last statement of this section fails the step in that case.
-- (qid 1, 25 and 33 are the first question of the particle, mixed and short
-- cases; the data is grouped that way, 8 per case.)

DROP TABLE IF EXISTS index_control;
CREATE TABLE index_control
(
    qid         UInt16,
    tok         String,
    fn          String,
    via_index   UInt32,
    via_arrays  UInt32,
    ok          UInt8
)
ENGINE = MergeTree ORDER BY (qid, tok, fn);

INSERT INTO index_control
SELECT p.qid, p.tok, p.fn, p.via_index, e.n_returned, p.via_index = e.n_returned
FROM
(
    SELECT 1 AS qid, 'splitByNonAlpha' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_nonalpha, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'splitByNonAlpha' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_nonalpha, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'asciiCJK' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_cjk, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'asciiCJK' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_cjk, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'ngrams(2)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_ng2, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'ngrams(2)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_ng2, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'ngrams(3)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_ng3, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'ngrams(3)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_ng3, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'sparseGrams' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_sparse, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'sparseGrams' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_sparse, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'icu(ko)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_icu, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'icu(ko)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_icu, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'splitByRegexp' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_regexp, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'splitByRegexp' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_regexp, (SELECT question FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'kiwi' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(morphemes, (SELECT morphemes FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 1 AS qid, 'kiwi' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(morphemes, (SELECT morphemes FROM queries WHERE qid = 1))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'splitByNonAlpha' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_nonalpha, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'splitByNonAlpha' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_nonalpha, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'asciiCJK' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_cjk, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'asciiCJK' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_cjk, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'ngrams(2)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_ng2, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'ngrams(2)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_ng2, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'ngrams(3)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_ng3, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'ngrams(3)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_ng3, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'sparseGrams' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_sparse, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'sparseGrams' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_sparse, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'icu(ko)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_icu, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'icu(ko)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_icu, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'splitByRegexp' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_regexp, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'splitByRegexp' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_regexp, (SELECT question FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'kiwi' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(morphemes, (SELECT morphemes FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 25 AS qid, 'kiwi' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(morphemes, (SELECT morphemes FROM queries WHERE qid = 25))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'splitByNonAlpha' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_nonalpha, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'splitByNonAlpha' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_nonalpha, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'asciiCJK' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_cjk, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'asciiCJK' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_cjk, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'ngrams(2)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_ng2, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'ngrams(2)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_ng2, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'ngrams(3)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_ng3, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'ngrams(3)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_ng3, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'sparseGrams' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_sparse, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'sparseGrams' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_sparse, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'icu(ko)' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_icu, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'icu(ko)' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_icu, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'splitByRegexp' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(b_regexp, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'splitByRegexp' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(b_regexp, (SELECT question FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'kiwi' AS tok, 'any' AS fn, (SELECT count() FROM chunks WHERE hasAnyTokens(morphemes, (SELECT morphemes FROM queries WHERE qid = 33))) AS via_index
    UNION ALL
    SELECT 33 AS qid, 'kiwi' AS tok, 'all' AS fn, (SELECT count() FROM chunks WHERE hasAllTokens(morphemes, (SELECT morphemes FROM queries WHERE qid = 33))) AS via_index
) AS p
INNER JOIN recall_eval AS e ON e.qid = p.qid AND e.tok = p.tok AND e.fn = p.fn;

SELECT c.qid, c.tok, c.fn, c.via_index, c.via_arrays, c.ok
FROM index_control AS c
INNER JOIN tokenizers AS t ON t.tok = c.tok
ORDER BY c.qid, t.ord, c.fn = 'all'
FORMAT TSVWithNames;

-- Fails the step (and so `tools/hol run`) when any row above has ok = 0.
SELECT throwIf(countIf(NOT ok) > 0 OR count() != 48, 'positive control failed: the token arrays disagree with the text index') AS control_failed
FROM index_control
FORMAT TSVWithNames;

SELECT '════════ 4. Recall and precision ════════' AS section;

-- Output A. One row per tokenizer x fn, averaged over all questions.
--   recall / precision  macro average over questions (precision counts 0 when
--                       nothing was returned)
--   avg_returned        mean |R|: how many chunks a RAG pipeline would have to
--                       read or rerank per question. 300 would be "everything".
-- Read `any` as the recall ceiling and `all` as the precise end; the useful
-- tokenizers are the ones where both look reasonable.
SELECT
    t.tok AS tok,
    e.fn AS fn,
    round(avg(e.n_hit / e.n_relevant), 3)                          AS recall,
    round(avg(if(e.n_returned = 0, 0, e.n_hit / e.n_returned)), 3) AS precision,
    round(avg(e.n_returned), 1)                                    AS avg_returned
FROM recall_eval AS e
INNER JOIN tokenizers AS t ON t.tok = e.tok
GROUP BY t.ord, t.tok, e.fn
ORDER BY t.ord, e.fn = 'all'
FORMAT TSVWithNames;

-- Output B. Recall by failure case, one row per tokenizer x fn. Each column is
-- the mean recall over the questions of that case, so it shows which kind of
-- question a tokenizer gets wrong.
SELECT
    e.fn AS fn,
    t.tok AS tok,
    round(avgIf(e.n_hit / e.n_relevant, e.fcase = 'particle'), 3) AS particle,
    round(avgIf(e.n_hit / e.n_relevant, e.fcase = 'spacing'), 3)  AS spacing,
    round(avgIf(e.n_hit / e.n_relevant, e.fcase = 'ending'), 3)   AS ending,
    round(avgIf(e.n_hit / e.n_relevant, e.fcase = 'mixed'), 3)    AS mixed,
    round(avgIf(e.n_hit / e.n_relevant, e.fcase = 'short'), 3)    AS short
FROM recall_eval AS e
INNER JOIN tokenizers AS t ON t.tok = e.tok
GROUP BY e.fn, t.ord, t.tok
ORDER BY e.fn = 'all', t.ord
FORMAT TSVWithNames;
