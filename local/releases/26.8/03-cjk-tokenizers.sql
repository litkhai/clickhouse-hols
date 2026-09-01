-- ClickHouse 26.8 — CJK and ICU tokenizers for text indexes
--
-- 26.8 adds three tokenizers: `japanese`, `chinese` and `icu`. For anyone
-- indexing Korean, Japanese or Chinese this is the difference between a text
-- index that works and one that does not, because the tokenizers that came
-- before all assume words are separated by spaces.
--
-- Korean does separate words with spaces, so it looks like it should have been
-- fine all along. It was not, and section 1 shows why.

SELECT '════════ 1. What the old tokenizers did to Korean ════════' AS section;

SELECT 'unicodeWord' AS tokenizer, tokens('클릭하우스 벡터 검색은 빠르다', 'unicodeWord') AS result
UNION ALL
SELECT 'asciiCJK',    tokens('클릭하우스 벡터 검색은 빠르다', 'asciiCJK')
UNION ALL
SELECT 'chinese',     tokens('클릭하우스 벡터 검색은 빠르다', 'chinese')
UNION ALL
SELECT 'icu(ko)',     tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko');

-- unicodeWord and asciiCJK split Korean into individual syllables:
--   ['클','릭','하','우','스','벡','터', …]
--
-- Thirteen tokens for four words. A text index built on that matches almost
-- everything and prunes almost nothing — the worst of both.
--
-- chinese and icu produce actual words:
--   ['클릭하우스','벡터','검색은','빠르다']

SELECT '════════ 2. icu needs a locale, and then ignores it ════════' AS section;

-- Passing 'icu' without a locale is an error, not a default:
--   Code: 36. Tokenizer 'icu' requires a mandatory locale argument, e.g. icu('en')

-- And it has to be a constant. Feeding it a column is rejected:
--   Code: 44. A value of illegal type was provided as 3rd argument 'locale'
--   to function 'tokens'. Expected: const String, got: String
--
-- so the comparison has to be written out.

SELECT 'ko'    AS locale, tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko')    AS result
UNION ALL
SELECT 'ko_KR' AS locale, tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ko_KR') AS result
UNION ALL
SELECT 'en'    AS locale, tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'en')    AS result
UNION ALL
SELECT 'ja'    AS locale, tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'ja')    AS result
UNION ALL
SELECT 'zh'    AS locale, tokens('클릭하우스 벡터 검색은 빠르다', 'icu', 'zh')    AS result;

-- Every locale returns the same tokens. ICU's word-break for Korean comes from
-- a built-in dictionary rather than from the locale tag, so the argument is
-- required but does not change this result. Worth knowing before you spend an
-- afternoon tuning it.

SELECT '════════ 3. Mixed scripts ════════' AS section;

SELECT tokens('ClickHouse 벡터검색 ベクトル検索 2026년', 'icu', 'ko') AS mixed;
-- ['ClickHouse','벡터검색','ベクトル','検索','2026','년']
--
-- Latin stays whole, Korean and Japanese are segmented, and the number splits
-- from its unit. That last one is a choice you may or may not want.

SELECT '════════ 4. Building a text index ════════' AS section;

SET allow_experimental_full_text_index = 1;

-- The syntax is a function call, not a string plus a separate argument:
--   tokenizer = icu('ko')            correct
--   tokenizer = 'icu', locale = 'ko' rejected
DROP TABLE IF EXISTS docs;
CREATE TABLE docs
(
    id   UInt32,
    body String,
    INDEX idx body TYPE text(tokenizer = icu('ko')) GRANULARITY 1
)
ENGINE = MergeTree ORDER BY id;

INSERT INTO docs VALUES
    (1, '클릭하우스 벡터 검색은 빠르다'),
    (2, '포스트그레스 전문검색 비교'),
    (3, 'ClickHouse text index 테스트');

SELECT id, tokens(body, 'icu', 'ko') AS indexed_tokens FROM docs ORDER BY id;

SELECT '-- a token that exists' AS probe;
SELECT id, body FROM docs WHERE hasToken(body, '벡터');

SELECT '════════ 5. The limitation you must plan around ════════' AS section;

SELECT '-- searching for 검색 finds nothing' AS probe;
SELECT count() AS matches FROM docs WHERE hasToken(body, '검색');

SELECT '-- because the token is 검색은, with the particle attached' AS probe;
SELECT id FROM docs WHERE hasToken(body, '검색은');

-- Korean particles (조사) stay glued to the noun. 검색은 / 검색을 / 검색이 are
-- three different tokens, and none of them is 검색:
SELECT tokens('검색은 검색을 검색이', 'icu', 'ko') AS particles_are_not_stripped;

-- This is word segmentation, not morphological analysis. ICU finds word
-- boundaries; it does not know that 은/을/이 are grammar rather than spelling.
-- Options, in the order most people should consider them:
--
--   1. Search with the particle, if your users type whole phrases.
--   2. Index a second column pre-processed by a Korean morphological analyser
--      (mecab-ko, nori, kiwi) outside ClickHouse, and index that with
--      splitByString. You keep control and pay an ingest step.
--   3. Use ngrams for recall-first search and accept the index size.
--
-- What you should not do is assume icu('ko') behaves like a Korean analyser.
-- It is a large improvement over per-syllable splitting and it is not that.

SELECT '════════ 6. The other two tokenizers ════════' AS section;

SELECT 'chinese' AS tokenizer, tokens('点击之家向量搜索很快', 'chinese') AS result
UNION ALL
SELECT 'icu(zh)' AS tokenizer, tokens('点击之家向量搜索很快', 'icu', 'zh') AS result;

-- For Chinese the two disagree, and `chinese` is the better of them:
--   chinese  ['点击','之家','向量','搜索','很快']
--   icu(zh)  ['点','击','之家','向量','搜索','很快']
-- ICU splits 点击 into two characters; the dedicated tokenizer keeps the word.
-- For Korean they were identical. Test on your own corpus rather than picking
-- by name.
--
-- `japanese` is listed in system.tokenizers but needs a dictionary supplied in
-- the server configuration:
--
--   Code: 139. The Japanese tokenizer requires a dictionary configured under
--   <tokenizer><japanese> in the server configuration
--
-- so it does not work out of the box in this container. icu handles Japanese
-- without extra configuration, which is the pragmatic choice for a mixed
-- corpus.
SELECT tokens('ベクトル検索は速い', 'icu', 'ja') AS japanese_via_icu;

SELECT '════════ 7. Everything the server offers ════════' AS section;

SELECT groupArray(name) AS all_tokenizers FROM system.tokenizers;

-- Cleanup left commented so you can keep poking at the table.
-- DROP TABLE IF EXISTS docs;
