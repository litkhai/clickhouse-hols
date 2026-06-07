-- ============================================================================
-- Full-Text Search Lab · Step 1: Schema for Bilingual Support Ticket Search
-- 풀텍스트 검색 실습 · Step 1: 한/영 고객지원 티켓 검색용 스키마
-- ============================================================================
-- Created: 2026-06-07
-- Use case: A Korean SaaS commerce platform "ClickStore" receives ~1M
--           customer-support tickets per quarter. Agents need sub-second
--           search across subject + body + resolution + tags, in mixed
--           Korean (한국어) and English text.
--
-- We build FOUR copies of the same ticket table, each with a different
-- indexing strategy. Identical data will be loaded into all four in
-- 02-load.sql so that step 04 can compare query latency, disk usage,
-- and recall side-by-side.
--
--   tickets_noidx   — no skip index, baseline (full scan)
--   tickets_token   — tokenbf_v1     (legacy whitespace-token bloom filter)
--   tickets_ngram   — ngrambf_v1     (legacy n-gram bloom filter, CJK-safe)
--   tickets_text    — text(...)      (GA inverted index from 26.2+;
--                                     two columns: asciiCJK + ngrams(2))
--
-- Requirement: ClickHouse 26.2+ (text index is GA).
-- On 25.x ClickHouse Cloud, the text index column is created but the
-- engine falls back to a brute-force scan — still valid for comparison.
-- ============================================================================

DROP DATABASE IF EXISTS support_search;
CREATE DATABASE support_search;

-- Safety net for older clusters that still mark text index experimental.
-- 25.x 클러스터에서 text 인덱스가 아직 실험적으로 표시되는 경우를 위한 안전장치.
SET allow_experimental_full_text_index = 1;
SET allow_experimental_inverted_index = 1;

-- ----------------------------------------------------------------------------
-- 1.0 Common enum definitions (used by every variant table)
-- 1.0 공통 enum 정의 (모든 변형 테이블에서 동일하게 사용)
-- ----------------------------------------------------------------------------
-- Categories cover the most common Korean e-commerce support intents.
-- Statuses follow Zendesk-style ticket lifecycle.

-- ----------------------------------------------------------------------------
-- 1.1 Baseline table — no full-text index at all
-- 1.1 베이스라인 테이블 — 풀텍스트 인덱스 없음
-- ----------------------------------------------------------------------------
-- Every search hits a full column scan. This is our "ground truth" both
-- for performance (worst case) and for recall (no false negatives).
-- ----------------------------------------------------------------------------
CREATE TABLE support_search.tickets_noidx (
    ticket_id       UInt64,
    customer_id     UInt32,
    agent_id        UInt32,
    category        LowCardinality(String),     -- 결제/배송/환불/로그인/계정/버그/기능요청/사용법
    priority        Enum8('critical'=1,'high'=2,'medium'=3,'low'=4),
    status          Enum8('open'=1,'in_progress'=2,'pending'=3,'resolved'=4,'closed'=5),
    channel         LowCardinality(String),     -- email / chat / web / mobile_app / phone
    product         LowCardinality(String),     -- product the ticket is about
    language        LowCardinality(String),     -- ko / en / mixed
    subject         String,                     -- short subject line
    body            String,                     -- full ticket body (mixed ko/en)
    resolution      String,                     -- agent's resolution note (may be empty)
    tags            Array(String),              -- free-form tags
    created_at      DateTime,
    resolved_at     Nullable(DateTime)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, ticket_id)
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- 1.2 tokenbf_v1 — whitespace-token bloom filter (legacy)
-- 1.2 tokenbf_v1 — 공백 토큰 블룸 필터 (구버전)
-- ----------------------------------------------------------------------------
-- Splits text on non-alphanumeric chars then bloom-filters tokens.
-- Works well for English, but for Korean it tokenizes by 어절 (eojeol):
--   "결제가 안돼요" → ["결제가", "안돼요"]
-- So a search for "결제" will MISS this row — that's the limitation we
-- demonstrate in 05-korean-limits.sql.
-- ----------------------------------------------------------------------------
CREATE TABLE support_search.tickets_token (
    ticket_id       UInt64,
    customer_id     UInt32,
    agent_id        UInt32,
    category        LowCardinality(String),
    priority        Enum8('critical'=1,'high'=2,'medium'=3,'low'=4),
    status          Enum8('open'=1,'in_progress'=2,'pending'=3,'resolved'=4,'closed'=5),
    channel         LowCardinality(String),
    product         LowCardinality(String),
    language        LowCardinality(String),
    subject         String,
    body            String,
    resolution      String,
    tags            Array(String),
    created_at      DateTime,
    resolved_at     Nullable(DateTime),

    -- Bloom-filter on whitespace/punct-tokenized subject+body.
    -- size_of_bloom_filter_in_bytes=8192, number_of_hash_functions=3, seed=0
    INDEX idx_subject_token  subject  TYPE tokenbf_v1(8192, 3, 0) GRANULARITY 4,
    INDEX idx_body_token     body     TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, ticket_id)
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- 1.3 ngrambf_v1 — n-gram bloom filter (CJK-safe but bloom-only)
-- 1.3 ngrambf_v1 — n-gram 블룸 필터 (CJK 안전, 단 블룸 필터일 뿐)
-- ----------------------------------------------------------------------------
-- N=3 trigrams. Korean syllables are 3 UTF-8 bytes each, so a trigram bloom
-- on bytes does NOT align with Hangul boundaries; we use N=3 here against
-- characters, which means roughly 1 Hangul syllable per gram. For 2-char
-- queries the filter will return many false positives and ClickHouse will
-- still need to verify with LIKE/match. That is fine — bloom is a pruner,
-- not a final answer.
--
-- A trigram index lets queries like "결제" (2 chars) prune at the part
-- level but each part must still scan to confirm. A 4-char query like
-- "결제 실패" produces multiple trigrams and prunes hard.
-- ----------------------------------------------------------------------------
CREATE TABLE support_search.tickets_ngram (
    ticket_id       UInt64,
    customer_id     UInt32,
    agent_id        UInt32,
    category        LowCardinality(String),
    priority        Enum8('critical'=1,'high'=2,'medium'=3,'low'=4),
    status          Enum8('open'=1,'in_progress'=2,'pending'=3,'resolved'=4,'closed'=5),
    channel         LowCardinality(String),
    product         LowCardinality(String),
    language        LowCardinality(String),
    subject         String,
    body            String,
    resolution      String,
    tags            Array(String),
    created_at      DateTime,
    resolved_at     Nullable(DateTime),

    -- ngrambf_v1(n, size_bytes, hash_fns, seed). n=3 covers Korean well.
    INDEX idx_subject_ngram subject TYPE ngrambf_v1(3, 8192, 3, 0)  GRANULARITY 4,
    INDEX idx_body_ngram    body    TYPE ngrambf_v1(3, 32768, 3, 0) GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, ticket_id)
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- 1.4 text index — modern inverted index (GA in ClickHouse 26.2+)
-- 1.4 text 인덱스 — 최신 역인덱스 (ClickHouse 26.2+ GA)
-- ----------------------------------------------------------------------------
-- Unlike bloom filters, this is a real per-token posting list. Granularity 1
-- means one posting list per granule, giving the tightest pruning.
--
-- We build TWO indexes on the SAME body column so 04-index-comparison.sql
-- can compare tokenizers on identical data:
--   • body_cjk   uses tokenizer = asciiCJK   — best for mixed ko+en text
--                  (treats each Hangul syllable cluster as a token plus
--                   ASCII words; respects Unicode word boundaries)
--   • body_gram  uses tokenizer = ngrams(2)  — substring index, language-
--                  agnostic, larger on disk but most forgiving for partial
--                  Korean matches.
-- ----------------------------------------------------------------------------
CREATE TABLE support_search.tickets_text (
    ticket_id       UInt64,
    customer_id     UInt32,
    agent_id        UInt32,
    category        LowCardinality(String),
    priority        Enum8('critical'=1,'high'=2,'medium'=3,'low'=4),
    status          Enum8('open'=1,'in_progress'=2,'pending'=3,'resolved'=4,'closed'=5),
    channel         LowCardinality(String),
    product         LowCardinality(String),
    language        LowCardinality(String),
    subject         String,
    body            String,
    resolution      String,
    tags            Array(String),
    created_at      DateTime,
    resolved_at     Nullable(DateTime),

    -- asciiCJK tokenizer — best general-purpose index for mixed Korean+English
    INDEX idx_subject_cjk  subject TYPE text(tokenizer = 'asciiCJK')   GRANULARITY 1,
    INDEX idx_body_cjk     body    TYPE text(tokenizer = 'asciiCJK')   GRANULARITY 1,

    -- ngrams(2) tokenizer — substring matching for short Korean fragments
    INDEX idx_body_gram2   body    TYPE text(tokenizer = 'ngrams', ngram_size = 2) GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, ticket_id)
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- 1.5 Knowledge base articles (for FAQ matching in 06-real-scenarios.sql)
-- 1.5 지식베이스 문서 (06-real-scenarios.sql의 FAQ 매칭용)
-- ----------------------------------------------------------------------------
CREATE TABLE support_search.articles (
    article_id      UInt32,
    category        LowCardinality(String),
    language        LowCardinality(String),
    title           String,
    body            String,
    keywords        Array(String),
    views           UInt32 DEFAULT 0,
    helpful_votes   UInt32 DEFAULT 0,
    updated_at      DateTime DEFAULT now(),

    INDEX idx_title_cjk title TYPE text(tokenizer = 'asciiCJK') GRANULARITY 1,
    INDEX idx_body_cjk  body  TYPE text(tokenizer = 'asciiCJK') GRANULARITY 1
)
ENGINE = MergeTree
ORDER BY article_id
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- 1.6 Ticket messages (multi-turn conversation, for "similar ticket" search)
-- 1.6 티켓 메시지 (멀티턴 대화, '유사 티켓' 검색용)
-- ----------------------------------------------------------------------------
CREATE TABLE support_search.ticket_messages (
    ticket_id       UInt64,
    message_seq     UInt16,
    sender          Enum8('customer'=1,'agent'=2,'system'=3),
    sent_at         DateTime,
    body            String,

    INDEX idx_msg_cjk body TYPE text(tokenizer = 'asciiCJK') GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(sent_at)
ORDER BY (ticket_id, message_seq)
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- Sanity check: list created tables
-- 확인: 생성된 테이블 목록
-- ----------------------------------------------------------------------------
SELECT name, engine, total_rows
FROM system.tables
WHERE database = 'support_search'
ORDER BY name;
