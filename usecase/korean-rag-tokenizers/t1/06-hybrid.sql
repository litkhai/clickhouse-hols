-- Korean RAG keyword search — step 6: vector search, and the two together
--
-- Steps 3 to 5 asked how far a keyword filter gets. Some questions it cannot
-- answer whatever the tokenizer: the question says 아웃룩 or 팀즈 where the chunks
-- only say Outlook or Teams, so the two share no token at all. A dense embedding
-- does not need a shared token; it maps both to nearby points. This step
-- embeds the chunks and the questions with bge-m3, ranks by vector distance, and
-- then merges that ranking with the keyword ranking of step 4.
--
--   1. a named collection pointing aiEmbed at a local Ollama
--   2. embed every chunk and every question (stored in two tables)
--   3. the vector index, shown in use for one question
--   4. rank: vector top 20 per question, then reciprocal rank fusion with the
--      keyword lists of step 4 (two keyword setups: kiwi and ngrams(2))
--   5. results: recall@5, recall@10, MRR@10 per method, per failure case, and
--      per question for the `mixed` case
--
-- T1: this step needs an Ollama server with the bge-m3 model, so it is not part
-- of `tools/hol run` (which runs only the top-level NN-*.sql files). Run
-- t1/06-hybrid.sh instead: it checks Ollama, gives the `default` user the right
-- to create a named collection, and pipes this file through clickhouse-client.
-- It also needs steps 0 to 4 to have run in the same container
-- (`tools/hol run usecase/korean-rag-tokenizers --keep`): this file reads
-- korean_rag.chunks, korean_rag.queries and korean_rag.keyword_ranked.
--
-- Running it again is safe: tables are dropped and rebuilt, and the named
-- collection is created only if it does not exist.

USE korean_rag;

SELECT '════════ 1. aiEmbed against a local Ollama ════════' AS section;

-- aiEmbed(text, model) calls an embedding endpoint. Where it calls, and with
-- which key, comes from a named collection. The `openai` provider speaks the
-- OpenAI embeddings API, which Ollama also serves under /v1/embeddings; Ollama
-- ignores the key, but the field is part of the collection.
--
-- host.docker.internal is how a container on Docker Desktop reaches the host,
-- where Ollama listens on 11434. On Linux the container has no such name unless
-- it was started with --add-host=host.docker.internal:host-gateway.
--
-- Creating a named collection needs named_collection_control for the user; the
-- `default` user of the image does not have it. t1/06-hybrid.sh adds it through
-- a users.d file and SYSTEM RELOAD CONFIG before this file runs.
CREATE NAMED COLLECTION IF NOT EXISTS ollama_embed AS
    provider = 'openai',
    endpoint = 'http://host.docker.internal:11434/v1/embeddings',
    api_key = '';

-- The AI functions are experimental and refuse a plain-http endpoint unless told
-- otherwise; the third setting names the collection to use when a call gives no
-- credentials of its own. These settings last for this session only.
SET allow_experimental_ai_functions = 1;
SET ai_function_allow_insecure_endpoint = 1;
SET ai_function_embedding_default_credentials = 'ollama_embed';

SELECT '════════ 2. Embed chunks and questions ════════' AS section;

-- chunk_vec holds one 1024-number vector per chunk. The index is an HNSW graph
-- over cosine distance. Its last argument is the number of dimensions and must
-- equal what the model returns: a vector of another length is rejected on
-- INSERT. That is why the length check below is the recorded dimension.
DROP TABLE IF EXISTS chunk_vec;
CREATE TABLE chunk_vec
(
    id   UInt32,
    emb  Array(Float32),
    INDEX iv emb TYPE vector_similarity('hnsw', 'cosineDistance', 1024)
)
ENGINE = MergeTree ORDER BY id;

INSERT INTO chunk_vec
SELECT id, aiEmbed(body, 'bge-m3') FROM chunks;

-- The questions are embedded the same way. The question text goes in as it is,
-- with no instruction prefix.
DROP TABLE IF EXISTS query_vec;
CREATE TABLE query_vec
(
    qid  UInt16,
    emb  Array(Float32)
)
ENGINE = MergeTree ORDER BY qid;

INSERT INTO query_vec
SELECT qid, aiEmbed(question, 'bge-m3') FROM queries;

-- Every row should have the same length: min_dim = max_dim = the model's
-- dimension, and the same number as in the index definition above.
SELECT tbl, vectors, min_dim, max_dim
FROM
(
    SELECT 1 AS ord, 'chunk_vec' AS tbl, count() AS vectors, min(length(emb)) AS min_dim, max(length(emb)) AS max_dim FROM chunk_vec
    UNION ALL
    SELECT 2, 'query_vec', count(), min(length(emb)), max(length(emb)) FROM query_vec
)
ORDER BY ord
FORMAT TSVWithNames;

SELECT '════════ 3. The vector index in use ════════' AS section;

-- ORDER BY a distance with LIMIT is the shape a vector index answers. The query
-- vector comes from a scalar subquery, as the needle of hasAnyTokens did in
-- step 1. Of the plan, only the index's own lines are kept: the name, what it
-- is, and the Granules line. An empty name means the index did not take part.
-- (With 300 rows the table is a single granule, so there is nothing to prune;
-- what to look at is that `iv` is in the plan.)
-- (The plan is drawn as a tree; replaceRegexpOne strips the drawing characters
-- in front of each line.)
SELECT replaceRegexpOne(lines[p], '^[^A-Za-z]+', '') AS index_line,
       replaceRegexpOne(arrayFirst(l -> position(l, 'Description:') > 0, arraySlice(lines, if(p = 0, 1, p))), '^[^A-Za-z]+', '') AS description,
       replaceRegexpOne(arrayFirst(l -> position(l, 'Granules:') > 0, arraySlice(lines, if(p = 0, 1, p))), '^[^A-Za-z]+', '') AS granules
FROM
(
    SELECT lines, arrayFirstIndex(l -> position(l, 'Name:') > 0, lines) AS p
    FROM
    (
        SELECT groupArray(explain) AS lines
        FROM
        (
            EXPLAIN indexes = 1
            SELECT id FROM chunk_vec
            ORDER BY cosineDistance(emb, (SELECT emb FROM query_vec WHERE qid = 1))
            LIMIT 10
        )
    )
)
FORMAT TSVWithNames;

-- The same query, run: the ten nearest chunks to question 1 (a particle
-- question). `relevant` is 1 where the chunk is in the hand-labelled set.
SELECT
    row_number() OVER (ORDER BY v.dist, v.id) AS rnk,
    v.id AS id,
    round(v.dist, 4) AS dist,
    has((SELECT relevant FROM queries WHERE qid = 1), v.id) AS relevant,
    substringUTF8(c.body, 1, 30) AS body_start
FROM
(
    SELECT id, cosineDistance(emb, (SELECT emb FROM query_vec WHERE qid = 1)) AS dist
    FROM chunk_vec
    ORDER BY dist
    LIMIT 10
) AS v
INNER JOIN chunks AS c ON c.id = v.id
ORDER BY rnk
FORMAT TSVWithNames;

SELECT '════════ 4. Rank: vector, keyword, and both ════════' AS section;

-- The evaluation below does not go through the index. It computes the exact
-- distance from every question to every chunk (40 x 300 pairs), so the numbers
-- measure the embedding, not the approximation of the graph. The index path is
-- the single-question form above; the control at the end of this section checks
-- that for question 1 the two agree.
--
-- vector_ranked: the 20 nearest chunks per question, like keyword_ranked of
-- step 4 (ties in distance are broken by id).
DROP TABLE IF EXISTS vector_ranked;
CREATE TABLE vector_ranked
(
    qid   UInt16,
    id    UInt32,
    dist  Float32,
    rnk   UInt16
)
ENGINE = MergeTree ORDER BY (qid, rnk);

INSERT INTO vector_ranked
SELECT qid, id, dist, rnk
FROM
(
    SELECT
        qid, id, dist,
        row_number() OVER (PARTITION BY qid ORDER BY dist ASC, id ASC) AS rnk
    FROM
    (
        SELECT q.qid AS qid, c.id AS id, cosineDistance(c.emb, q.emb) AS dist
        FROM query_vec AS q
        CROSS JOIN chunk_vec AS c
    )
)
WHERE rnk <= 20;

-- The five methods, in display order. `keyword` rows are the ranked lists of
-- step 4 for one tokenizer; `hybrid` merges them with the vector list.
DROP TABLE IF EXISTS hybrid_methods;
CREATE TABLE hybrid_methods
(
    ord     UInt8,
    method  String
)
ENGINE = MergeTree ORDER BY ord;

INSERT INTO hybrid_methods VALUES
    (1, 'vector'),
    (2, 'keyword kiwi'),
    (3, 'keyword ngrams(2)'),
    (4, 'hybrid vector+kiwi'),
    (5, 'hybrid vector+ngrams(2)');

-- hybrid_ranked: the top 10 of every method for every question, one row per
-- method x question x chunk. The first three methods are plain copies of a
-- ranked list; a question the keyword filter returned nothing for simply has no
-- rows for that method.
DROP TABLE IF EXISTS hybrid_ranked;
CREATE TABLE hybrid_ranked
(
    ord  UInt8,
    qid  UInt16,
    id   UInt32,
    rnk  UInt16
)
ENGINE = MergeTree ORDER BY (ord, qid, rnk);

INSERT INTO hybrid_ranked
SELECT 1, qid, id, rnk FROM vector_ranked WHERE rnk <= 10
UNION ALL
SELECT 2, qid, id, rnk FROM keyword_ranked WHERE tok = 'kiwi' AND rnk <= 10
UNION ALL
SELECT 3, qid, id, rnk FROM keyword_ranked WHERE tok = 'ngrams(2)' AND rnk <= 10;

-- Reciprocal rank fusion (Cormack, Clarke and Buettcher, SIGIR 2009): a chunk
-- gets 1 / (k + rank) from every list it appears in, the scores are added, and
-- chunks are ordered by the sum. k = 60 is the value of that paper. It uses only
-- ranks, so the two lists need no common scale: a cosine distance and a count
-- of matched tokens are never compared. Both lists contribute their top 20.
-- A chunk in both lists beats a chunk that is first in only one of them; a
-- question with no keyword rows gets the vector list unchanged. Ties are broken
-- by id.
INSERT INTO hybrid_ranked
SELECT 4, qid, id, rnk
FROM
(
    SELECT qid, id, row_number() OVER (PARTITION BY qid ORDER BY score DESC, id ASC) AS rnk
    FROM
    (
        SELECT qid, id, sum(1 / (60 + rnk)) AS score
        FROM
        (
            SELECT qid, id, rnk FROM vector_ranked
            UNION ALL
            SELECT qid, id, rnk FROM keyword_ranked WHERE tok = 'kiwi'
        )
        GROUP BY qid, id
    )
)
WHERE rnk <= 10;

INSERT INTO hybrid_ranked
SELECT 5, qid, id, rnk
FROM
(
    SELECT qid, id, row_number() OVER (PARTITION BY qid ORDER BY score DESC, id ASC) AS rnk
    FROM
    (
        SELECT qid, id, sum(1 / (60 + rnk)) AS score
        FROM
        (
            SELECT qid, id, rnk FROM vector_ranked
            UNION ALL
            SELECT qid, id, rnk FROM keyword_ranked WHERE tok = 'ngrams(2)'
        )
        GROUP BY qid, id
    )
)
WHERE rnk <= 10;

-- A check on the lists themselves: for each method, how many questions have a
-- list at all and how long the lists are. `vector` and the two hybrids should
-- cover all 40 questions with 10 chunks each; a keyword method covers fewer
-- when some questions share no token with any chunk.
SELECT
    m.method AS method,
    uniqExact(r.qid) AS questions_with_a_list,
    round(count() / uniqExact(r.qid), 1) AS avg_list_length
FROM hybrid_ranked AS r
INNER JOIN hybrid_methods AS m ON m.ord = r.ord
GROUP BY m.ord, m.method
ORDER BY m.ord
FORMAT TSVWithNames;

-- Control for the exact-distance choice: question 1's ten nearest chunks by the
-- index (section 3) against the ten of vector_ranked. same_set = 1 means the
-- index returned what the exact computation did. The index is approximate, so
-- on a larger table this can legitimately be 0.
SELECT
    arraySort(ix.ids) AS index_top10,
    arraySort(ex.ids) AS exact_top10,
    arraySort(ix.ids) = arraySort(ex.ids) AS same_set
FROM
(
    SELECT groupArray(id) AS ids
    FROM
    (
        SELECT id FROM chunk_vec
        ORDER BY cosineDistance(emb, (SELECT emb FROM query_vec WHERE qid = 1))
        LIMIT 10
    )
) AS ix
CROSS JOIN
(
    SELECT groupArray(id) AS ids FROM vector_ranked WHERE qid = 1 AND rnk <= 10
) AS ex
FORMAT TSVWithNames;

SELECT '════════ 5. Results ════════' AS section;

-- hybrid_eval: one row per method x question, as ranking_eval in step 4.
--   n_relevant  |G|, the hand-labelled chunks
--   h5, h10     relevant chunks within the first 5 / 10 of the list
--   rr10        1 / rank of the first relevant chunk in the top 10, 0 if none
-- A question a method returns nothing for has all zeros.
DROP TABLE IF EXISTS hybrid_eval;
CREATE TABLE hybrid_eval
(
    ord         UInt8,
    qid         UInt16,
    fcase       LowCardinality(String),
    n_relevant  UInt8,
    h5          UInt8,
    h10         UInt8,
    rr10        Float64
)
ENGINE = MergeTree ORDER BY (ord, qid);

INSERT INTO hybrid_eval
SELECT b.ord, b.qid, b.fcase, b.n_relevant, r.h5, r.h10, r.rr
FROM
(
    SELECT m.ord AS ord, qs.qid AS qid, qs.fcase AS fcase, length(qs.relevant) AS n_relevant
    FROM hybrid_methods AS m
    CROSS JOIN queries AS qs
) AS b
LEFT JOIN
(
    SELECT
        k.ord AS ord, k.qid AS qid,
        countIf(k.rnk <= 5  AND has(qs.relevant, k.id)) AS h5,
        countIf(k.rnk <= 10 AND has(qs.relevant, k.id)) AS h10,
        max(if(k.rnk <= 10 AND has(qs.relevant, k.id), 1 / k.rnk, 0)) AS rr
    FROM hybrid_ranked AS k
    INNER JOIN queries AS qs ON qs.qid = k.qid
    GROUP BY k.ord, k.qid
) AS r ON r.ord = b.ord AND r.qid = b.qid;

-- Output A. Recall@5, recall@10 (macro average over the 40 questions: relevant
-- chunks found in the first k / all relevant chunks) and MRR@10. The two keyword
-- rows are the ranked numbers of step 4 for kiwi and ngrams(2), so this table
-- reads as "step 4's best, vector, and the merge of the two". The lab does not
-- fix which keyword setup is the final one; both are kept.
SELECT
    m.method AS method,
    round(avg(e.h5  / e.n_relevant), 3) AS recall5,
    round(avg(e.h10 / e.n_relevant), 3) AS recall10,
    round(avg(e.rr10), 3)               AS mrr10
FROM hybrid_eval AS e
INNER JOIN hybrid_methods AS m ON m.ord = e.ord
GROUP BY m.ord, m.method
ORDER BY m.ord
FORMAT TSVWithNames;

-- Output B. Recall@10 by failure case. Look for where each method is strong:
-- keyword for particle, spacing and ending once the tokenizer normalises them,
-- vector where the words differ, and whether the merge keeps the better of the
-- two in each column or loses some of it.
SELECT
    m.method AS method,
    round(avgIf(e.h10 / e.n_relevant, e.fcase = 'particle'), 3) AS particle,
    round(avgIf(e.h10 / e.n_relevant, e.fcase = 'spacing'), 3)  AS spacing,
    round(avgIf(e.h10 / e.n_relevant, e.fcase = 'ending'), 3)   AS ending,
    round(avgIf(e.h10 / e.n_relevant, e.fcase = 'mixed'), 3)    AS mixed,
    round(avgIf(e.h10 / e.n_relevant, e.fcase = 'short'), 3)    AS short
FROM hybrid_eval AS e
INNER JOIN hybrid_methods AS m ON m.ord = e.ord
GROUP BY m.ord, m.method
ORDER BY m.ord
FORMAT TSVWithNames;

-- Output C. Recall@10 of each method for the eight `mixed` questions, one row
-- per question, with the note that says what the trap is. The questions that
-- use a Korean transliteration (아웃룩, 팀즈) where the chunks only have the
-- English word are the ones no tokenizer can fix: a keyword method has nothing
-- to match, so look at what the vector method and the hybrids do with them.
SELECT
    qs.qid AS qid,
    qs.question AS question,
    round(anyIf(e.h10 / e.n_relevant, e.ord = 1), 2) AS vector,
    round(anyIf(e.h10 / e.n_relevant, e.ord = 2), 2) AS kw_kiwi,
    round(anyIf(e.h10 / e.n_relevant, e.ord = 3), 2) AS kw_ngrams2,
    round(anyIf(e.h10 / e.n_relevant, e.ord = 4), 2) AS hyb_kiwi,
    round(anyIf(e.h10 / e.n_relevant, e.ord = 5), 2) AS hyb_ngrams2,
    qs.note AS note
FROM hybrid_eval AS e
INNER JOIN queries AS qs ON qs.qid = e.qid
WHERE e.fcase = 'mixed'
GROUP BY qs.qid, qs.question, qs.note
ORDER BY qs.qid
FORMAT TSVWithNames;
