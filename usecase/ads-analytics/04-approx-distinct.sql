-- ============================================================================
-- ads-analytics Step 4: High-Cardinality Distinct Counts (uniq vs uniqExact)
-- ads-analytics 4단계: 고카디널리티 고유값 카운트 (uniq vs uniqExact)
-- ============================================================================
-- userId / deviceId / requestId have millions of distinct values. Exact counts
-- (uniqExact) hold every value in memory; approximate counts (uniq, HyperLogLog)
-- use a fixed tiny footprint with ~1-2% error. For dashboards & exploration use
-- uniq; for billing/settlement use uniqExact.
-- userId / deviceId / requestId는 distinct 수가 수백만. 정확 카운트(uniqExact)는
-- 모든 값을 메모리에 보관하고, 근사 카운트(uniq, HyperLogLog)는 고정된 작은
-- 메모리로 ~1-2% 오차를 냄. 대시보드·탐색은 uniq, 정산·과금은 uniqExact 권장.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 4.1 Approximate vs exact — same column, error & relationship
-- 4.1 근사 vs 정확 — 동일 컬럼, 오차와 관계
-- ---------------------------------------------------------------------------

SELECT
    uniqExact(deviceId)                                                 AS devices_exact,
    uniq(deviceId)                                                      AS devices_approx,
    uniqCombined(deviceId)                                              AS devices_combined,
    round(abs(uniq(deviceId) - uniqExact(deviceId)) * 100.0
          / uniqExact(deviceId), 3)                                     AS uniq_err_pct,
    round(abs(uniqCombined(deviceId) - uniqExact(deviceId)) * 100.0
          / uniqExact(deviceId), 3)                                     AS combined_err_pct
FROM ad_analytics.ad_events;

-- ---------------------------------------------------------------------------
-- 4.2 Daily Active Users / Devices (DAU) — approximate is the right default
-- 4.2 일별 액티브 사용자/디바이스 (DAU) — 근사가 기본값으로 적합
-- ---------------------------------------------------------------------------

SELECT
    toDate(eventTs)   AS day,
    uniq(userId)      AS dau_users,
    uniq(deviceId)    AS dau_devices,
    uniq(requestId)   AS bid_requests
FROM   ad_analytics.ad_events
WHERE  eventTs >= '2026-06-08'
GROUP  BY day
ORDER  BY day;

-- ---------------------------------------------------------------------------
-- 4.3 Conditional distinct — uniqIf (count distinct only on a sub-population)
-- 4.3 조건부 고유값 — uniqIf (특정 부분집합에 대해서만 distinct)
-- ---------------------------------------------------------------------------
-- "How many distinct campaigns / line items actually got an impression?"
-- "실제로 노출이 발생한 캠페인·라인아이템은 몇 개인가?"

SELECT
    channelType,
    uniqIf(campaignId, eventType = 'IMPRESSION')                        AS active_campaigns,
    uniqIf(lineItemId, eventType = 'IMPRESSION')                        AS active_line_items,
    uniqIf(accountId,  eventType = 'IMPRESSION')                        AS active_accounts,
    -- distinct catalog items pulled from the creativeAsset JSON
    -- creativeAsset JSON에서 추출한 고유 아이템 수
    uniqIf(JSONExtractString(creativeAsset, 'item', 'id'),
           eventType = 'IMPRESSION')                                    AS active_items
FROM   ad_analytics.ad_events
GROUP  BY channelType
ORDER  BY channelType;

-- ---------------------------------------------------------------------------
-- 4.4 Reach & per-user economics
-- 4.4 도달(Reach)과 사용자 단위 경제성
-- ---------------------------------------------------------------------------
-- Reach per line item = distinct users / distinct line items.
-- Revenue/Spending per user normalize money by audience size.
-- 라인아이템당 도달 = 고유 사용자 / 고유 라인아이템.
-- 사용자당 매출·소진액은 금액을 오디언스 크기로 정규화.
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    campaignId,
    uniq(userId)                                                       AS reach_users,
    round(uniq(userId) / nullIf(uniqIf(lineItemId, eventType = 'IMPRESSION'), 0), 1)
                                                                       AS reach_per_line_item,
    round(sumIf(conversionValue,
                eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION'))
          / SCALE / nullIf(uniq(userId), 0), 4)                        AS revenue_per_user,
    round(sumIf(winPrice, eventType = 'CLICK')
          / nullIf(uniq(userId), 0) / SCALE, 4)                        AS spending_per_user,
    round(countIf(eventType = 'CLICK') * 1.0 / nullIf(uniq(userId), 0), 4)
                                                                       AS clicks_per_user
FROM   ad_analytics.ad_events
GROUP  BY campaignId
ORDER  BY reach_users DESC
LIMIT  10;

-- ---------------------------------------------------------------------------
-- 4.5 Frequency capping check — impressions per user distribution
-- 4.5 프리퀀시 캡 점검 — 사용자당 노출 분포
-- ---------------------------------------------------------------------------
-- A two-level aggregation: count impressions per user, then bucket users.
-- 2단계 집계: 사용자별 노출 수를 센 뒤, 사용자를 버킷으로 묶음.
SELECT
    imp_per_user,
    count()                                                            AS users
FROM (
    SELECT userId, countIf(eventType = 'IMPRESSION') AS imp_per_user
    FROM   ad_analytics.ad_events
    WHERE  userId IS NOT NULL
    GROUP  BY userId
)
GROUP  BY imp_per_user
ORDER  BY imp_per_user
LIMIT  10;

SELECT 'Step 4 complete — approximate distincts scale; reserve uniqExact for billing.' AS done;
