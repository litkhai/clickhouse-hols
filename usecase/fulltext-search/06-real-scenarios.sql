-- ============================================================================
-- Full-Text Search Lab · Step 6: Real Operational Scenarios
-- 풀텍스트 검색 실습 · Step 6: 실제 운영 시나리오
-- ============================================================================
-- These are queries that a real customer-support team runs every day.
-- Each one would be slow or impossible without a full-text index — and they
-- get progressively more sophisticated, ending with a Materialized View
-- that powers an agent dashboard in O(ms).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 6.1 Live agent search bar — "find the ticket about ___"
-- 6.1 상담사 라이브 검색바
-- ----------------------------------------------------------------------------
-- A senior agent typing into their search bar. Sub-200ms target on 1M rows.
-- Highlights both Korean and English query terms in the snippet column.
-- ----------------------------------------------------------------------------
WITH 'PAYMENT_DECLINED 결제 실패' AS q
SELECT
    ticket_id,
    created_at,
    category,
    priority,
    status,
    substringUTF8(subject, 1, 60) AS subj,
    -- snippet: ±30 chars (UTF-8 char count) around the first match
    -- 첫 매치 위치 기준 ±30자 (UTF-8 문자 단위) 발췌
    substringUTF8(
        body,
        greatest(1, toInt32(positionUTF8(body, splitByChar(' ', q)[1])) - 30),
        80
    ) AS snippet
FROM support_search.tickets_text
WHERE hasAnyTokens(body, splitByChar(' ', q))
ORDER BY created_at DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- 6.2 Trending issue detection — what blew up in the last 24h?
-- 6.2 급증 이슈 탐지 — 최근 24시간에 무엇이 폭증했나?
-- ----------------------------------------------------------------------------
-- Compare keyword frequency in the last day vs the prior 7-day baseline.
-- Anything spiking 3x+ is flagged for the ops Slack channel.
-- ----------------------------------------------------------------------------
WITH watch_terms AS (
    SELECT ['PAYMENT_DECLINED','TIMEOUT','ERROR 502','OAuth','카카오페이','네이버페이','결제 실패','로그인 안','배송 지연','환불 거절'] AS terms
),
recent AS (
    SELECT arrayJoin((SELECT terms FROM watch_terms)) AS term, count() AS c
    FROM support_search.tickets_text
    WHERE created_at >= now() - INTERVAL 1 DAY
      AND positionUTF8(body, term) > 0
    GROUP BY term
),
baseline AS (
    SELECT arrayJoin((SELECT terms FROM watch_terms)) AS term, count() / 7.0 AS daily_avg
    FROM support_search.tickets_text
    WHERE created_at BETWEEN now() - INTERVAL 8 DAY AND now() - INTERVAL 1 DAY
      AND positionUTF8(body, term) > 0
    GROUP BY term
)
SELECT
    r.term,
    r.c AS last_24h,
    round(b.daily_avg, 1) AS baseline_per_day,
    round(r.c / nullIf(b.daily_avg, 0), 2) AS spike_ratio
FROM recent r LEFT JOIN baseline b USING term
ORDER BY spike_ratio DESC NULLS LAST;

-- ----------------------------------------------------------------------------
-- 6.3 Similar-ticket suggestion — given a new ticket, find related ones
-- 6.3 유사 티켓 추천 — 새 티켓이 들어올 때 관련 티켓 찾기
-- ----------------------------------------------------------------------------
-- Take a sample "new" ticket, extract its salient tokens, and find the
-- top-K resolved tickets that share the most tokens. This is the basic
-- "agent assist" feature most support tools sell.
-- ----------------------------------------------------------------------------
WITH new_ticket AS (
    SELECT body FROM support_search.tickets_noidx WHERE ticket_id = 42 LIMIT 1
),
candidate_tokens AS (
    -- Extract Korean tokens (≥2 hangul ≈ ≥6 UTF-8 bytes, no ASCII chars)
    -- and English tokens (≥4 ASCII letters). These become our query OR-list.
    -- 한국어 2자+ / 영어 4자+ 토큰을 후보 쿼리로 추출
    SELECT arrayDistinct(arrayFilter(
        t -> (length(t) >= 6 AND notMatch(t, '[A-Za-z0-9_]'))
          OR (length(t) >= 4 AND match(t, '^[A-Za-z]+$')),
        splitByRegexp('[\\s.,!?;:()\\[\\]"\\d]+', (SELECT body FROM new_ticket))
    )) AS tokens
)
SELECT
    t.ticket_id,
    t.created_at,
    t.status,
    -- score = number of shared tokens
    -- 점수 = 공통 토큰 개수
    arrayCount(x -> positionUTF8(t.body, x) > 0, (SELECT tokens FROM candidate_tokens)) AS shared_tokens,
    substring(t.subject, 1, 60) AS subject,
    t.resolution
FROM support_search.tickets_text t
WHERE t.ticket_id != 42
  AND t.status IN ('resolved','closed')
  AND hasAnyTokens(t.body, (SELECT tokens FROM candidate_tokens))
ORDER BY shared_tokens DESC, t.created_at DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- 6.4 FAQ auto-match — point new tickets at existing knowledge-base articles
-- 6.4 FAQ 자동 매칭 — 새 티켓에 적합한 KB 문서 추천
-- ----------------------------------------------------------------------------
-- Joining a ticket against the article body using the article's keywords as
-- the tokenized search. This is the no-ML version of the "did you mean?"
-- box at the top of a help desk.
-- ----------------------------------------------------------------------------
WITH sample_tickets AS (
    SELECT ticket_id, body, category FROM support_search.tickets_text
    WHERE status IN ('open','in_progress')
    ORDER BY created_at DESC
    LIMIT 20
)
SELECT
    s.ticket_id,
    s.category,
    a.article_id,
    a.title,
    arrayCount(k -> positionUTF8(s.body, k) > 0, a.keywords) AS keyword_hits
FROM sample_tickets s
LEFT JOIN support_search.articles a ON s.category = a.category
WHERE arrayCount(k -> positionUTF8(s.body, k) > 0, a.keywords) > 0
ORDER BY s.ticket_id, keyword_hits DESC
LIMIT 30;

-- A simpler alternative — full-cross approach (10 articles × 5 tickets = trivial)
-- 더 간단한 대안 — 풀 cross 조인 (10 × 5 = 무시할 만함)
WITH sample AS (
    SELECT ticket_id, body FROM support_search.tickets_text
    WHERE ticket_id IN (1, 100, 1000, 50000, 500000)
)
SELECT
    s.ticket_id,
    a.article_id,
    a.title,
    -- score: how many of the article's keywords are in the ticket body
    arrayCount(k -> positionUTF8(s.body, k) > 0, a.keywords) AS keyword_hits
FROM sample s
CROSS JOIN support_search.articles a
WHERE arrayCount(k -> positionUTF8(s.body, k) > 0, a.keywords) >= 2
ORDER BY s.ticket_id, keyword_hits DESC;

-- ----------------------------------------------------------------------------
-- 6.5 MTTR by topic — which problem categories take the longest to resolve?
-- 6.5 주제별 MTTR — 어떤 문제가 가장 오래 걸리나
-- ----------------------------------------------------------------------------
-- Free-text categorization that complements the explicit `category` field:
-- find tickets whose body contains specific keywords and measure how long
-- they took to resolve.
-- ----------------------------------------------------------------------------
WITH topics AS (
    SELECT p.1 AS topic_name, p.2 AS needles
    FROM (
        SELECT arrayJoin([
            ('카드 결제 실패',    ['PAYMENT_DECLINED', '카드 결제']),
            ('OAuth/소셜 로그인', ['OAuth', '소셜 로그인', '카카오 로그인', '구글 로그인']),
            ('배송 지연',         ['배송 지연', '배송이 늦', '운송장이 없']),
            ('이중 결제',         ['이중 결제', '중복 결제']),
            ('환불 거절',         ['환불 거절', '환불이 안'])
        ]) AS p
    )
)
SELECT
    topic_name,
    count() AS tickets,
    countIf(resolved_at IS NOT NULL) AS resolved,
    round(avgIf(dateDiff('hour', created_at, resolved_at), resolved_at IS NOT NULL), 1) AS avg_hours_to_resolve,
    round(quantileIf(0.9)(dateDiff('hour', created_at, resolved_at), resolved_at IS NOT NULL), 1) AS p90_hours
FROM support_search.tickets_text t
CROSS JOIN topics
WHERE multiSearchAny(t.body, topics.needles)
GROUP BY topic_name
ORDER BY avg_hours_to_resolve DESC;

-- ----------------------------------------------------------------------------
-- 6.6 Conversation search — search within ticket messages, not just subject
-- 6.6 대화 검색 — 메시지 본문 검색
-- ----------------------------------------------------------------------------
-- Find tickets where the customer escalated after the first response.
-- 첫 응답 이후에 고객이 다시 문제를 호소한 티켓 찾기.
SELECT
    m.ticket_id,
    count() AS escalation_messages,
    groupArray(substring(m.body, 1, 40)) AS samples
FROM support_search.ticket_messages m
WHERE m.sender = 'customer'
  AND m.message_seq > 1
  AND multiSearchAny(m.body, ['답이 없', '아직 답변', '며칠째', 'Still waiting', '추가 정보'])
GROUP BY m.ticket_id
HAVING escalation_messages >= 1
ORDER BY escalation_messages DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- 6.7 Materialized view: pre-tokenized topic counts for dashboards
-- 6.7 머티리얼라이즈드 뷰: 대시보드용 사전 집계
-- ----------------------------------------------------------------------------
-- For a CS dashboard refreshing every minute, scanning 1M tickets per refresh
-- is wasteful. Pre-aggregate "did this ticket mention topic X" at write time.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS support_search.topic_daily;
CREATE TABLE support_search.topic_daily (
    day     Date,
    topic   LowCardinality(String),
    tickets AggregateFunction(count, UInt64)
) ENGINE = AggregatingMergeTree
ORDER BY (day, topic);

DROP VIEW IF EXISTS support_search.mv_topic_daily;
CREATE MATERIALIZED VIEW support_search.mv_topic_daily TO support_search.topic_daily AS
SELECT
    toDate(created_at) AS day,
    multiIf(
        multiSearchAny(body, ['PAYMENT_DECLINED','결제 실패','카드 결제']), 'billing-fail',
        multiSearchAny(body, ['배송 지연','배송이 늦','운송장이 없']),       'shipping-delay',
        multiSearchAny(body, ['환불 거절','환불이 안','환불 처리 안']),     'refund-stuck',
        multiSearchAny(body, ['로그인 안','로그인이 안','OAuth']),           'login-fail',
        'other'
    ) AS topic,
    countState() AS tickets
FROM support_search.tickets_text
GROUP BY day, topic;

-- Backfill from existing data (real workload would only see future inserts)
-- 기존 데이터 백필 — 실무에서는 신규 INSERT만 잡혀도 됨
INSERT INTO support_search.topic_daily
SELECT
    toDate(created_at) AS day,
    multiIf(
        multiSearchAny(body, ['PAYMENT_DECLINED','결제 실패','카드 결제']), 'billing-fail',
        multiSearchAny(body, ['배송 지연','배송이 늦','운송장이 없']),       'shipping-delay',
        multiSearchAny(body, ['환불 거절','환불이 안','환불 처리 안']),     'refund-stuck',
        multiSearchAny(body, ['로그인 안','로그인이 안','OAuth']),           'login-fail',
        'other'
    ) AS topic,
    countState() AS tickets
FROM support_search.tickets_text
GROUP BY day, topic;

-- Dashboard query — milliseconds, regardless of base table size
-- 대시보드 쿼리 — 원천 테이블 크기와 무관하게 ms 단위
SELECT
    day,
    topic,
    countMerge(tickets) AS n
FROM support_search.topic_daily
WHERE day >= today() - 30
GROUP BY day, topic
ORDER BY day DESC, n DESC
LIMIT 50;
