-- Korean RAG keyword search — step 1: what each tokenizer does to Korean
--
-- Step 0 loaded `phrases`: eleven short Korean phrases, each picking at one way
-- keyword search fails on Korean (particles, spacing, endings, mixed scripts,
-- one-syllable words). Here we only look at tokens — no index, no corpus yet.
--
-- Eight tokenizers are compared throughout the lab. Seven are ClickHouse's own
-- and run on the raw text; `kiwi` is the Kiwi morphological analyser, run outside
-- ClickHouse by gen_data.py, whose output sits in the `morphemes` column.
-- Everything string-based is lowercased first: `lower()` here, `preprocessor =
-- lower(col)` in the indexes later, so English and codes (VPN / vpn) line up.

USE korean_rag;

SELECT '════════ 1. Re-check of the 26.8 findings ════════' AS section;

-- local/releases/26.8/03-cjk-tokenizers.sql made three claims. Do they still
-- hold on this server?
--   a) asciiCJK splits Korean into single syllables
--   b) icu('ko') returns whole words, particles still attached (검색은)
--   c) the locale argument makes no difference

SELECT version() AS clickhouse_version
FORMAT TSVWithNames;

SELECT tokenizer, result
FROM
(
    SELECT 1 AS ord, 'asciiCJK' AS tokenizer, tokens('클릭하우스 벡터 검색은 빠르다', 'asciiCJK') AS result
    UNION ALL
    SELECT 2, 'icu(ko)',    tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko')
    UNION ALL
    SELECT 3, 'icu(ko_KR)', tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko_KR')
    UNION ALL
    SELECT 4, 'icu(en)',    tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'en')
    UNION ALL
    SELECT 5, 'icu(ja)',    tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ja')
)
ORDER BY ord
FORMAT TSVWithNames;

SELECT
    tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko') = tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko_KR')
    AND tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko') = tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'en')
    AND tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko') = tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ja')
    AS icu_same_for_all_four_locales
FORMAT TSVWithNames;

SELECT '════════ 2. Every phrase through every tokenizer ════════' AS section;

-- phrase_tokens is long-form: one row per phrase x tokenizer. `ord` is the
-- display order used by every later step. The regexp tokenizer is the lab's own:
-- it takes a run of letters or digits and drops one trailing particle
-- (은/는/이/가/을/를/에서/…), a rough particle stripper that needs no analyser.
-- With match_tokens = true the regexp's first group is the token; the
-- non-greedy `+?` lets the optional particle claim its characters first.
-- Backslashes are doubled because this is a SQL string literal.
--
-- It is a rule, not an analyser: a word that only ends in a particle-shaped
-- syllable is cut too. Run on 사이 and 나이 it returns ['사','나'].

DROP TABLE IF EXISTS phrase_tokens;
CREATE TABLE phrase_tokens
(
    pid     UInt8,
    fcase   String,
    phrase  String,
    ord     UInt8,
    tok     String,
    tokens  Array(String)
)
ENGINE = MergeTree ORDER BY (pid, ord);

INSERT INTO phrase_tokens
SELECT pid, fcase, phrase, 1 AS ord, 'splitByNonAlpha' AS tok, tokens(lower(phrase), 'splitByNonAlpha') FROM phrases
UNION ALL
SELECT pid, fcase, phrase, 2, 'asciiCJK',        tokens(lower(phrase), 'asciiCJK') FROM phrases
UNION ALL
SELECT pid, fcase, phrase, 3, 'ngrams(2)',       tokens(lower(phrase), 'ngrams', 2) FROM phrases
UNION ALL
SELECT pid, fcase, phrase, 4, 'ngrams(3)',       tokens(lower(phrase), 'ngrams', 3) FROM phrases
UNION ALL
SELECT pid, fcase, phrase, 5, 'sparseGrams',     tokens(lower(phrase), 'sparseGrams') FROM phrases
UNION ALL
SELECT pid, fcase, phrase, 6, 'icu(ko)',         tokens(lower(phrase), 'icu', 'ko') FROM phrases
UNION ALL
SELECT pid, fcase, phrase, 7, 'splitByRegexp',   tokens(lower(phrase), 'splitByRegexp', '([\\p{L}\\p{N}]+?)(?:은|는|이|가|을|를|에서|에게|에|의|로|으로|와|과|도|만)?(?:[^\\p{L}\\p{N}]|$)', true) FROM phrases
UNION ALL
SELECT pid, fcase, phrase, 8, 'kiwi',            morphemes FROM phrases;

-- Look at one phrase at a time: the eight rows of a pid are the eight
-- tokenizers on identical input. Compare 결재선은 / 결재선을 / 결재선이 (pid 2)
-- across them, and 구매요청서 vs 구매 요청서 (pids 3 and 4).
SELECT pid, fcase, phrase, tok, tokens
FROM phrase_tokens
ORDER BY pid, ord
FORMAT TSVWithNames;

SELECT '════════ 3. How many tokens each tokenizer makes ════════' AS section;

-- More tokens per phrase means more entries in the index and more candidate
-- chunks per lookup. Compare the asciiCJK and ngrams columns with kiwi.
SELECT
    pid,
    phrase,
    lengthUTF8(phrase)                          AS chars,
    sumIf(length(tokens), tok = 'splitByNonAlpha') AS `splitByNonAlpha`,
    sumIf(length(tokens), tok = 'asciiCJK')        AS `asciiCJK`,
    sumIf(length(tokens), tok = 'ngrams(2)')       AS `ngrams(2)`,
    sumIf(length(tokens), tok = 'ngrams(3)')       AS `ngrams(3)`,
    sumIf(length(tokens), tok = 'sparseGrams')     AS `sparseGrams`,
    sumIf(length(tokens), tok = 'icu(ko)')         AS `icu(ko)`,
    sumIf(length(tokens), tok = 'splitByRegexp')   AS `splitByRegexp`,
    sumIf(length(tokens), tok = 'kiwi')            AS `kiwi`
FROM phrase_tokens
GROUP BY pid, phrase
ORDER BY pid
FORMAT TSVWithNames;

SELECT '════════ 4. Two limits to know before step 2 ════════' AS section;

-- sparseGrams has a minimum length of 3. Asking for less is an error:
--
--   SELECT tokens('결재', 'sparseGrams', 2, 4);
--   Code: 36. Unexpected parameter of tokenizer 'sparseGrams':
--   minimal length must be at least 3, but got 2
--
-- and so a two-syllable Korean word, which is most of them, makes no token at
-- all. Not an error, just nothing:
SELECT tokens('결재', 'sparseGrams') AS sparseGrams_of_a_two_syllable_word
FORMAT TSVWithNames;

-- hasAnyTokens / hasAllTokens want a constant needle. A column, for instance
-- one that arrives through a join, is rejected:
--
--   SELECT hasAllTokens(body, q.question) FROM chunks, queries AS q ...;
--   Code: 44. A value of illegal type was provided as 2nd argument 'needles'
--   to function 'hasAllTokens'. Expected: const String or const Array(String),
--   got: String
--
-- A scalar subquery is a constant to the function, so this works, and when the
-- column has a text index the index is used (step 5 shows the plan). The
-- question is searched in itself, so the answer is 1 whatever the data:
SELECT hasAnyTokens(question, (SELECT question FROM queries WHERE qid = 1)) AS scalar_subquery_needle_accepted
FROM queries WHERE qid = 1
FORMAT TSVWithNames;

-- Steps 3 and 4 therefore compare token arrays with hasAny / hasAll instead of
-- looping a join through hasAnyTokens, and use the index functions only where
-- the needle can be written as a scalar subquery.
