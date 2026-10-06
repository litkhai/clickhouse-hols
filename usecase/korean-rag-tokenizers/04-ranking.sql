-- Korean RAG keyword search — step 4: ranking without BM25
--
-- Step 3 asked "which chunks come back?". A RAG pipeline passes only the first
-- few chunks to the model, so the order matters as much as the set. ClickHouse
-- has no BM25 for text indexes yet (the work is ClickHouse/ClickHouse#117519, an
-- open pull request "BM25 scoring for text index (basics)" when this was written,
-- 2026-10-06), so this step ranks with the simplest score that uses only the
-- token arrays from step 3:
--
--   score(question, chunk) = (distinct chunk tokens that are also question tokens)
--                            / (number of question tokens)
--
-- the fraction of the question's tokens that the chunk covers. Chunks with
-- score > 0 (exactly the `any` set of step 3) are ranked by score, highest
-- first; ties are broken by id. It does not weigh rare tokens above common ones,
-- which is the main thing BM25 adds, and a chunk's length plays no part.
--
-- The baseline is the same `any` set in id order, i.e. what a plain filter with
-- no ORDER BY hands back; "first k" of it is what a pipeline gets by cutting off.

USE korean_rag;

SELECT '════════ 1. Score and rank ════════' AS section;

-- keyword_ranked: the top 20 per tokenizer x question. Step 6 (the hybrid step)
-- reads it.
DROP TABLE IF EXISTS keyword_ranked;
CREATE TABLE keyword_ranked
(
    tok    LowCardinality(String),
    qid    UInt16,
    id     UInt32,
    score  Float64,
    rnk    UInt16
)
ENGINE = MergeTree ORDER BY (tok, qid, rnk);

INSERT INTO keyword_ranked
SELECT tok, qid, id, score, rnk
FROM
(
    SELECT
        tok, qid, id, score,
        row_number() OVER (PARTITION BY tok, qid ORDER BY score DESC, id ASC) AS rnk
    FROM
    (
        SELECT
            q.tok AS tok,
            q.qid AS qid,
            c.id AS id,
            length(arrayIntersect(arrayDistinct(c.toks), q.toks)) / length(q.toks) AS score
        FROM query_tokens AS q
        INNER JOIN chunk_tokens AS c ON c.tok = q.tok
        WHERE notEmpty(q.toks)
    )
    WHERE score > 0
)
WHERE rnk <= 20;

-- What a ranked list looks like: the top three chunks for question 1 under two
-- tokenizers. `relevant` is 1 where the chunk is in the hand-labelled set.
SELECT
    t.tok AS tok,
    r.rnk AS rnk,
    r.id AS id,
    round(r.score, 3) AS score,
    has(qs.relevant, r.id) AS relevant,
    substringUTF8(c.body, 1, 30) AS body_start
FROM keyword_ranked AS r
INNER JOIN tokenizers AS t ON t.tok = r.tok
INNER JOIN queries AS qs ON qs.qid = r.qid
INNER JOIN chunks AS c ON c.id = r.id
WHERE r.qid = 1 AND r.tok IN ('ngrams(2)', 'kiwi') AND r.rnk <= 3
ORDER BY t.ord, r.rnk
FORMAT TSVWithNames;

SELECT '════════ 2. Evaluate ranked and unranked ════════' AS section;

-- ranking_eval: one row per tokenizer x question.
--   ranked_h5 / ranked_h10      relevant chunks within the first 5 / 10 by score
--   unranked_h5 / unranked_h10  the same within the first 5 / 10 by id
--   rr10                        1 / rank of the first relevant chunk in the top
--                               10 by score, 0 if there is none
-- (a question that matches nothing has all zeros)
DROP TABLE IF EXISTS ranking_eval;
CREATE TABLE ranking_eval
(
    tok          LowCardinality(String),
    qid          UInt16,
    fcase        LowCardinality(String),
    n_relevant   UInt8,
    ranked_h5    UInt8,
    ranked_h10   UInt8,
    unranked_h5  UInt8,
    unranked_h10 UInt8,
    rr10         Float64
)
ENGINE = MergeTree ORDER BY (tok, qid);

INSERT INTO ranking_eval
SELECT
    b.tok, b.qid, b.fcase, b.n_relevant,
    r.h5, r.h10, u.h5, u.h10, r.rr
FROM
(
    SELECT q.tok AS tok, q.qid AS qid, qs.fcase AS fcase, length(qs.relevant) AS n_relevant
    FROM query_tokens AS q
    INNER JOIN queries AS qs ON qs.qid = q.qid
) AS b
LEFT JOIN
(
    SELECT
        k.tok AS tok, k.qid AS qid,
        countIf(k.rnk <= 5  AND has(qs.relevant, k.id)) AS h5,
        countIf(k.rnk <= 10 AND has(qs.relevant, k.id)) AS h10,
        max(if(k.rnk <= 10 AND has(qs.relevant, k.id), 1 / k.rnk, 0)) AS rr
    FROM keyword_ranked AS k
    INNER JOIN queries AS qs ON qs.qid = k.qid
    GROUP BY k.tok, k.qid
) AS r ON r.tok = b.tok AND r.qid = b.qid
LEFT JOIN
(
    -- the any-match set in id order
    SELECT
        m.tok AS tok, m.qid AS qid,
        countIf(m.urnk <= 5  AND has(qs.relevant, m.id)) AS h5,
        countIf(m.urnk <= 10 AND has(qs.relevant, m.id)) AS h10
    FROM
    (
        SELECT
            q.tok AS tok, q.qid AS qid, c.id AS id,
            row_number() OVER (PARTITION BY q.tok, q.qid ORDER BY c.id) AS urnk
        FROM query_tokens AS q
        INNER JOIN chunk_tokens AS c ON c.tok = q.tok
        WHERE hasAny(c.toks, q.toks)
    ) AS m
    INNER JOIN queries AS qs ON qs.qid = m.qid
    GROUP BY m.tok, m.qid
) AS u ON u.tok = b.tok AND u.qid = b.qid;

SELECT '════════ 3. Results ════════' AS section;

-- Output A. Recall@5 and @10 (macro average over questions, relevant chunks
-- found in the first k / all relevant chunks), with and without ranking, and
-- MRR@10 for the ranked list. The gap between the ranked and unranked columns
-- is what the score buys; where a tokenizer returns few chunks per question
-- there is little to reorder and the two columns are close.
SELECT
    t.tok AS tok,
    round(avg(e.ranked_h5    / e.n_relevant), 3) AS ranked_r5,
    round(avg(e.ranked_h10   / e.n_relevant), 3) AS ranked_r10,
    round(avg(e.unranked_h5  / e.n_relevant), 3) AS unranked_r5,
    round(avg(e.unranked_h10 / e.n_relevant), 3) AS unranked_r10,
    round(avg(e.rr10), 3)                        AS mrr10_ranked
FROM ranking_eval AS e
INNER JOIN tokenizers AS t ON t.tok = e.tok
GROUP BY t.ord, t.tok
ORDER BY t.ord
FORMAT TSVWithNames;

-- Output B. Ranked recall@10 by failure case.
SELECT
    t.tok AS tok,
    round(avgIf(e.ranked_h10 / e.n_relevant, e.fcase = 'particle'), 3) AS particle,
    round(avgIf(e.ranked_h10 / e.n_relevant, e.fcase = 'spacing'), 3)  AS spacing,
    round(avgIf(e.ranked_h10 / e.n_relevant, e.fcase = 'ending'), 3)   AS ending,
    round(avgIf(e.ranked_h10 / e.n_relevant, e.fcase = 'mixed'), 3)    AS mixed,
    round(avgIf(e.ranked_h10 / e.n_relevant, e.fcase = 'short'), 3)    AS short
FROM ranking_eval AS e
INNER JOIN tokenizers AS t ON t.tok = e.tok
GROUP BY t.ord, t.tok
ORDER BY t.ord
FORMAT TSVWithNames;

-- Output C. The same at k = 5: a RAG prompt rarely holds more.
SELECT
    t.tok AS tok,
    round(avgIf(e.ranked_h5 / e.n_relevant, e.fcase = 'particle'), 3) AS particle,
    round(avgIf(e.ranked_h5 / e.n_relevant, e.fcase = 'spacing'), 3)  AS spacing,
    round(avgIf(e.ranked_h5 / e.n_relevant, e.fcase = 'ending'), 3)   AS ending,
    round(avgIf(e.ranked_h5 / e.n_relevant, e.fcase = 'mixed'), 3)    AS mixed,
    round(avgIf(e.ranked_h5 / e.n_relevant, e.fcase = 'short'), 3)    AS short
FROM ranking_eval AS e
INNER JOIN tokenizers AS t ON t.tok = e.tok
GROUP BY t.ord, t.tok
ORDER BY t.ord
FORMAT TSVWithNames;
