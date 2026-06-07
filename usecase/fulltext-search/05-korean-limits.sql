-- ============================================================================
-- Full-Text Search Lab · Step 5: Korean-Specific Limitations
-- 풀텍스트 검색 실습 · Step 5: 한국어 검색의 구조적 한계
-- ============================================================================
-- Korean has no built-in morphological analyzer in ClickHouse, so a naive
-- tokenizer ALWAYS misses some legitimate matches. Each section below shows
-- a different category of failure with a measurable recall gap so you can
-- decide which tokenizer/strategy fits your dataset.
--
-- "Ground truth" = tickets_noidx + LIKE/positionUTF8 (a full scan that has
-- 100% recall by definition).
-- ============================================================================

SET use_query_cache = 0;

-- ----------------------------------------------------------------------------
-- 5.1 The 조사 (particle) problem
-- 5.1 조사 문제
-- ----------------------------------------------------------------------------
-- Korean attaches grammatical particles directly to nouns: 결제 + 가 = 결제가.
-- A whitespace-tokenizer treats "결제가", "결제는", "결제를", "결제도" as
-- four DIFFERENT tokens. Searching for "결제" misses them all.
--
-- Below: count how many tickets really mention 결제 (ground truth) vs how
-- many a whitespace token-search finds.
-- ----------------------------------------------------------------------------
SELECT 'ground truth: positionUTF8 = full scan' AS method, count() AS hits
FROM support_search.tickets_noidx
WHERE positionUTF8(body, '결제') > 0
UNION ALL
SELECT 'hasToken on tokenbf_v1: whitespace token equality', count()
FROM support_search.tickets_token
WHERE hasToken(body, '결제')
UNION ALL
SELECT 'hasToken on text(asciiCJK): unicode word boundary', count()
FROM support_search.tickets_text
WHERE hasToken(body, '결제');

-- Show the actual eojeol that swallow 결제 — these are what tokenizers split on.
-- 결제를 포함한 어절들 — 토크나이저가 만들어내는 토큰의 모습.
SELECT token, count() AS freq
FROM (
    SELECT arrayJoin(splitByRegexp('[\\s.,!?;:()\\[\\]]+', body)) AS token
    FROM support_search.tickets_noidx
    WHERE positionUTF8(body, '결제') > 0
)
WHERE token LIKE '%결제%'
GROUP BY token
ORDER BY freq DESC
LIMIT 15;

-- ----------------------------------------------------------------------------
-- 5.2 The spacing (띄어쓰기) problem
-- 5.2 띄어쓰기 문제
-- ----------------------------------------------------------------------------
-- Korean spacing rules are loose in informal writing. Customers write:
--   "로그인이 안 됩니다"   (correct)
--   "로그인이 안됩니다"     (common informal)
--   "로그인안됨"             (chat-style)
--
-- For a whitespace tokenizer these are three different token streams.
-- The lab data contains all three variants — let's see what each method finds.
-- ----------------------------------------------------------------------------
WITH
    full_scan AS (
        SELECT count() AS c FROM support_search.tickets_noidx
        WHERE multiSearchAny(body, ['로그인이 안 됩니다','로그인이 안됩니다','로그인안됨','로그인이 안돼요'])
    ),
    text_phrase AS (
        SELECT count() AS c FROM support_search.tickets_text
        WHERE hasPhrase(body, '로그인이 안 됩니다')
    ),
    text_any_token AS (
        SELECT count() AS c FROM support_search.tickets_text
        WHERE hasAllTokens(body, ['로그인','안','됩니다'])
    ),
    ngram_like AS (
        SELECT count() AS c FROM support_search.tickets_ngram
        WHERE body LIKE '%로그인%' AND body LIKE '%안 됩%'
    )
SELECT
    (SELECT c FROM full_scan)      AS ground_truth_any_variant,
    (SELECT c FROM text_phrase)    AS exact_phrase_only,
    (SELECT c FROM text_any_token) AS all_three_tokens,
    (SELECT c FROM ngram_like)     AS ngram_substring;

-- ----------------------------------------------------------------------------
-- 5.3 The stem vs ending (어간/어미) problem
-- 5.3 어간/어미 문제
-- ----------------------------------------------------------------------------
-- "안돼요 / 안됩니다 / 안 됨 / 안돼" all express the same meaning.
-- ClickHouse has no Korean stemmer, so each surface form is a different
-- token. Two main workarounds in practice:
--   (a) ngrams(2) tokenizer — catches the common "안돼" / "안 됩" bigrams
--   (b) build an application-side normalization layer that rewrites the
--       query into a disjunction.
-- ----------------------------------------------------------------------------
SELECT '안돼요'    AS variant, count() AS hits FROM support_search.tickets_noidx WHERE positionUTF8(body, '안돼요') > 0
UNION ALL
SELECT '안 됩니다', count() FROM support_search.tickets_noidx WHERE positionUTF8(body, '안 됩니다') > 0
UNION ALL
SELECT '안됩니다',  count() FROM support_search.tickets_noidx WHERE positionUTF8(body, '안됩니다') > 0
UNION ALL
SELECT '안 됨',    count() FROM support_search.tickets_noidx WHERE positionUTF8(body, '안 됨') > 0
ORDER BY hits DESC;

-- Workaround via application-side disjunction:
-- 애플리케이션 측 OR 확장 우회법:
SELECT count() AS total_negation_variants
FROM support_search.tickets_text
WHERE multiSearchAny(body, ['안돼요','안 됩니다','안됩니다','안 됨','안돼','안되','안 돼요']);

-- ----------------------------------------------------------------------------
-- 5.4 Short query / single-character problem
-- 5.4 짧은 쿼리 / 단일 자모 문제
-- ----------------------------------------------------------------------------
-- A trigram index needs at least 3 chars to query effectively. A bigram
-- index needs at least 2. Single Hangul characters bypass index entirely.
--
-- This shows the cost of an over-short query: it forces a full scan even
-- when an index exists. Practical answer: enforce min-length=2 in the UI.
-- ----------------------------------------------------------------------------
SELECT 'single char "결" — ngrambf(3) cannot prune' AS note, count() AS hits, max(read_rows) AS rows_read
FROM support_search.tickets_ngram
WHERE positionUTF8(body, '결') > 0;

SELECT 'two-char "결제" — bigram tokenizer prunes' AS note, count() AS hits
FROM support_search.tickets_text
WHERE hasToken(body, '결제');

-- ----------------------------------------------------------------------------
-- 5.5 Compound noun problem (복합명사)
-- 5.5 복합명사 문제
-- ----------------------------------------------------------------------------
-- "주문번호" is conceptually 주문 + 번호 but written as one word. A user
-- searching for "주문 번호" (with a space) misses the "주문번호" rows and
-- vice-versa.
--
-- This shows the recall delta between the two surface forms.
-- ----------------------------------------------------------------------------
SELECT '주문번호 (no space)' AS form, count() FROM support_search.tickets_noidx WHERE positionUTF8(body, '주문번호') > 0
UNION ALL
SELECT '주문 번호 (with space)', count() FROM support_search.tickets_noidx WHERE positionUTF8(body, '주문 번호') > 0;

-- Mitigation: search both forms simultaneously. The text index handles this
-- cleanly with hasAnyTokens once you normalize the query in your client.
-- 완화법: 두 형태를 모두 검색. 클라이언트 쿼리 정규화 후 hasAnyTokens 활용.
SELECT count() AS union_hits
FROM support_search.tickets_text
WHERE multiSearchAny(body, ['주문번호','주문 번호']);

-- ----------------------------------------------------------------------------
-- 5.6 Mixed-script word boundaries (한+영 혼용)
-- 5.6 한+영 혼용 단어 경계
-- ----------------------------------------------------------------------------
-- "iPhone15" vs "iPhone 15" vs "iPhone15Pro" — same product, three forms.
-- asciiCJK tokenizer treats ASCII alphanumeric as one token, but "15" inside
-- "iPhone15" is one token, while "iPhone 15" is two tokens.
--
-- Verify: query each form against the text index.
-- ----------------------------------------------------------------------------
SELECT 'iPhone 15 Pro (with spaces)' AS form, count() FROM support_search.tickets_text WHERE hasPhrase(body, 'iPhone 15 Pro')
UNION ALL
SELECT 'iPhone15Pro (no spaces)',   count() FROM support_search.tickets_text WHERE hasToken(body, 'iPhone15Pro')
UNION ALL
SELECT 'iPhone15 (partial join)',   count() FROM support_search.tickets_text WHERE hasToken(body, 'iPhone15');

-- ----------------------------------------------------------------------------
-- 5.7 Stop words you cannot ignore (불용어)
-- 5.7 무시할 수 없는 불용어
-- ----------------------------------------------------------------------------
-- English IR systems usually drop stop words ("the", "a"). Korean equivalents
-- ("저는", "그", "이") aren't filtered by ClickHouse tokenizers — they bloat
-- the index but don't help discriminate. The text index doesn't expose a
-- stop-word list yet, so the index is larger than it could be.
--
-- Quantify the bloat:
-- ----------------------------------------------------------------------------
SELECT 'top frequent Korean tokens (potential stop words)' AS note;
SELECT token, count() AS freq
FROM (
    SELECT arrayJoin(splitByRegexp('[\\s.,!?;:()\\[\\]]+', body)) AS token
    FROM support_search.tickets_noidx
    WHERE language = 'ko'
)
-- Korean-only: no ASCII letters/digits, and at least 2 hangul syllables (6 bytes).
-- 영숫자 없는 한국어 토큰만, 2음절(6바이트) 이상.
WHERE length(token) >= 6 AND notMatch(token, '[A-Za-z0-9_]')
GROUP BY token
ORDER BY freq DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- 5.8 Summary recall table — pick your trade-off
-- 5.8 요약 — 어떤 trade-off를 받아들일지 선택
-- ----------------------------------------------------------------------------
-- Run a fixed set of representative Korean queries against each table and
-- print the recall vs the ground-truth count. This is the single chart you
-- should screenshot for your team.
-- 대표 한국어 쿼리들로 recall을 비교 — 팀 공유용 단일 표.
-- ----------------------------------------------------------------------------
WITH queries AS (
    SELECT q, gt FROM (
        SELECT '결제'         AS q, (SELECT count() FROM support_search.tickets_noidx WHERE positionUTF8(body,'결제') > 0)         AS gt UNION ALL
        SELECT '환불 처리',         (SELECT count() FROM support_search.tickets_noidx WHERE positionUTF8(body,'환불 처리') > 0) UNION ALL
        SELECT '로그인이 안',       (SELECT count() FROM support_search.tickets_noidx WHERE positionUTF8(body,'로그인이 안') > 0) UNION ALL
        SELECT '안돼요',            (SELECT count() FROM support_search.tickets_noidx WHERE positionUTF8(body,'안돼요') > 0) UNION ALL
        SELECT '주문번호',          (SELECT count() FROM support_search.tickets_noidx WHERE positionUTF8(body,'주문번호') > 0) UNION ALL
        SELECT 'iPhone 결제',       (SELECT count() FROM support_search.tickets_noidx WHERE positionUTF8(body,'iPhone') > 0 AND positionUTF8(body,'결제') > 0)
    )
)
SELECT q, gt AS ground_truth FROM queries;

-- Practical advice printed at the end of the script:
SELECT '추천 (Recommendation):' AS note,
       '한/영 혼용 데이터에는 text(tokenizer=asciiCJK) + 클라이언트 쿼리 정규화(조사/띄어쓰기 변형 OR 확장) 조합이 가장 균형. 짧은 substring 검색이 잦으면 추가로 text(ngrams=2)를 같은 컬럼에 병행.' AS advice;
