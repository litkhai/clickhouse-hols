-- Korean RAG keyword search — step 2: one table, eight text indexes
--
-- A text index has exactly one tokenizer, so to compare tokenizers on the same
-- text each one needs its own copy of the text. The `chunks` table keeps the
-- original in `body` and adds one `MATERIALIZED body` column per ClickHouse
-- tokenizer; each of those columns carries one text index. The Kiwi tokens are
-- not computed by ClickHouse, they were loaded as `morphemes Array(String)`, and
-- that column is indexed with `tokenizer = array` (each element is a token).
--
-- Every String-based index has `preprocessor = lower(col)`, so the index stores
-- lowercase tokens and lowercases a String needle the same way. An Array needle
-- is used as it is.
--
-- index_granularity = 8 is deliberately tiny: with 300 rows it gives about 38
-- granules, so step 5 can show granule pruning on a table this small.
--
-- min_bytes_for_wide_part = 0 stores the part in the Wide format. A small part is
-- Compact by default, and system.columns reports 0 bytes for every column of a
-- Compact part, so step 5 could not tell how big `body` is.

USE korean_rag;

DROP TABLE IF EXISTS chunks;
CREATE TABLE chunks
(
    id         UInt32,
    doc        LowCardinality(String),
    body       String,
    morphemes  Array(String),

    b_nonalpha String MATERIALIZED body,
    b_cjk      String MATERIALIZED body,
    b_ng2      String MATERIALIZED body,
    b_ng3      String MATERIALIZED body,
    b_sparse   String MATERIALIZED body,
    b_icu      String MATERIALIZED body,
    b_regexp   String MATERIALIZED body,

    INDEX i_nonalpha b_nonalpha TYPE text(tokenizer = splitByNonAlpha, preprocessor = lower(b_nonalpha)),
    INDEX i_cjk      b_cjk      TYPE text(tokenizer = asciiCJK,        preprocessor = lower(b_cjk)),
    INDEX i_ng2      b_ng2      TYPE text(tokenizer = ngrams(2),       preprocessor = lower(b_ng2)),
    INDEX i_ng3      b_ng3      TYPE text(tokenizer = ngrams(3),       preprocessor = lower(b_ng3)),
    INDEX i_sparse   b_sparse   TYPE text(tokenizer = sparseGrams,     preprocessor = lower(b_sparse)),
    INDEX i_icu      b_icu      TYPE text(tokenizer = icu('ko'),       preprocessor = lower(b_icu)),
    -- the same particle-stripping pattern as step 1; match_tokens = true
    INDEX i_regexp   b_regexp   TYPE text(tokenizer = splitByRegexp('([\\p{L}\\p{N}]+?)(?:은|는|이|가|을|를|에서|에게|에|의|로|으로|와|과|도|만)?(?:[^\\p{L}\\p{N}]|$)', true),
                                          preprocessor = lower(b_regexp)),
    INDEX i_kiwi     morphemes  TYPE text(tokenizer = array)
)
ENGINE = MergeTree ORDER BY id
SETTINGS index_granularity = 8, min_bytes_for_wide_part = 0;

INSERT INTO chunks (id, doc, body, morphemes)
SELECT id, doc, body, morphemes FROM chunks_src;

-- A tokenizer registry the later steps join to: display order, the label used in
-- every output, the column the index is on, and the index name.
DROP TABLE IF EXISTS tokenizers;
CREATE TABLE tokenizers
(
    ord        UInt8,
    tok        String,
    col        String,
    index_name String
)
ENGINE = MergeTree ORDER BY ord;

INSERT INTO tokenizers VALUES
    (1, 'splitByNonAlpha', 'b_nonalpha', 'i_nonalpha'),
    (2, 'asciiCJK',        'b_cjk',      'i_cjk'),
    (3, 'ngrams(2)',       'b_ng2',      'i_ng2'),
    (4, 'ngrams(3)',       'b_ng3',      'i_ng3'),
    (5, 'sparseGrams',     'b_sparse',   'i_sparse'),
    (6, 'icu(ko)',         'b_icu',      'i_icu'),
    (7, 'splitByRegexp',   'b_regexp',   'i_regexp'),
    (8, 'kiwi',            'morphemes',  'i_kiwi');

SELECT '════════ 1. The indexes that exist ════════' AS section;

-- Eight rows, one per tokenizer, and the type each was created with.
SELECT t.ord, t.tok, i.name, i.type_full
FROM tokenizers AS t
INNER JOIN system.data_skipping_indices AS i
    ON i.name = t.index_name
WHERE i.database = 'korean_rag' AND i.table = 'chunks'
ORDER BY t.ord
FORMAT TSVWithNames;

SELECT '════════ 2. The data ════════' AS section;

SELECT count() AS chunks, uniqExact(doc) AS docs, (SELECT count() FROM queries) AS queries
FROM chunks
FORMAT TSVWithNames;

-- Same chunk, original text next to the Kiwi morphemes:
SELECT id, body, morphemes FROM chunks WHERE id = 1
FORMAT TSVWithNames;
