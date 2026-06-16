-- ============================================================================
-- ads-analytics Step 3: The Cube — Conditional Aggregation & Core KPIs
-- ads-analytics 3단계: 큐브 — 조건부 집계와 핵심 KPI
-- ============================================================================
-- The heart of an ad-analytics cube: every funnel metric is a *conditional*
-- aggregate (countIf / sumIf / avgIf) over the SAME wide table, computed in a
-- single vectorized pass. Group by ANY dimension to slice the cube.
-- 광고 분석 큐브의 핵심: 모든 퍼널 지표는 동일한 와이드 테이블에 대한 *조건부*
-- 집계(countIf / sumIf / avgIf)이며 단일 벡터화 패스로 계산됨. 아무 차원으로나
-- group by 하면 큐브를 슬라이스할 수 있음.
--
-- Money is stored as scaled integers; divide by SCALE for currency. SCALE and
-- take rates come from the cube_params table, never hard-coded.
-- 금액은 scaled integer; 통화 단위는 SCALE로 나눔. SCALE과 수수료율은 cube_params
-- 테이블에서 주입하고 하드코딩하지 않음.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 3.1 One-shot platform summary — all base counts in a single pass
-- 3.1 플랫폼 전체 요약 — 모든 기본 카운트를 단일 패스로
-- ---------------------------------------------------------------------------

SELECT
    countIf(eventType = 'IMPRESSION')                                   AS impressions,
    countIf(eventType = 'VIEWABLE_IMPRESSION')                          AS viewable,
    countIf(eventType = 'CLICK')                                        AS clicks,
    countIf(eventType = 'INTERACTION')                                  AS interactions,
    countIf(eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION'))  AS conversions,
    round(countIf(eventType = 'CLICK') * 100.0
          / nullIf(countIf(eventType = 'IMPRESSION'), 0), 3)            AS ctr_pct,
    round(countIf(eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) * 100.0
          / nullIf(countIf(eventType = 'CLICK'), 0), 3)                 AS cvr_pct
FROM ad_analytics.ad_events;

-- ---------------------------------------------------------------------------
-- 3.2 Campaign performance cube — the canonical reporting query
-- 3.2 캠페인 성과 큐브 — 표준 리포팅 쿼리
-- ---------------------------------------------------------------------------
-- Pull SCALE once as a scalar subquery so the divisor is parameterized.
-- SCALE을 스칼라 서브쿼리로 한 번만 가져와 나눗셈 인자를 파라미터화.
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    campaignId,
    countIf(eventType = 'IMPRESSION')                                   AS impressions,
    countIf(eventType = 'CLICK')                                        AS clicks,
    countIf(eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION'))  AS conversions,

    -- Spending = click-attributed win price ; Revenue = conversion value
    -- 소진액 = 클릭 기준 낙찰가 ; 매출 = 전환금액
    round(sumIf(winPrice, eventType = 'CLICK') / SCALE, 2)              AS spending,
    round(sumIf(conversionValue,
                eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) / SCALE, 2) AS revenue,

    -- Ratio KPIs: scale cancels out, so no /SCALE needed
    -- 비율 KPI: 스케일이 상쇄되므로 /SCALE 불필요
    round(countIf(eventType = 'CLICK') * 100.0
          / nullIf(countIf(eventType = 'IMPRESSION'), 0), 3)            AS ctr_pct,
    round(countIf(eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) * 100.0
          / nullIf(countIf(eventType = 'CLICK'), 0), 3)                 AS cvr_pct,
    round(sumIf(conversionValue,
                eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) * 100.0
          / nullIf(sumIf(winPrice, eventType = 'CLICK'), 0), 1)         AS roas_pct,

    -- Absolute-money KPIs DO need /SCALE
    -- 절대 금액 KPI는 /SCALE 필요
    round(sumIf(winPrice, eventType = 'CLICK')
          / nullIf(countIf(eventType = 'CLICK'), 0) / SCALE, 4)         AS cpc,
    round(sumIf(winPrice, eventType = 'CLICK')
          / nullIf(countIf(eventType = 'IMPRESSION'), 0) / SCALE * 1000, 4) AS cpm
FROM   ad_analytics.ad_events
GROUP  BY campaignId
ORDER  BY spending DESC
LIMIT  10;

-- ---------------------------------------------------------------------------
-- 3.3 Slice the SAME cube by a different dimension — channel x platform
-- 3.3 동일한 큐브를 다른 차원으로 슬라이스 — 채널 x 플랫폼
-- ---------------------------------------------------------------------------
-- No new table, no new index: just change the GROUP BY.
-- 새 테이블도 새 인덱스도 필요 없음: GROUP BY만 바꾸면 됨.
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    channelType,
    platform,
    countIf(eventType = 'IMPRESSION')                                   AS impressions,
    countIf(eventType = 'CLICK')                                        AS clicks,
    round(countIf(eventType = 'CLICK') * 100.0
          / nullIf(countIf(eventType = 'IMPRESSION'), 0), 3)            AS ctr_pct,
    round(sumIf(winPrice, eventType = 'CLICK') / SCALE, 2)              AS spending
FROM   ad_analytics.ad_events
GROUP  BY channelType, platform
ORDER  BY channelType, spending DESC;

-- ---------------------------------------------------------------------------
-- 3.4 Profit with parameterized take rates (NO hard-coded constants)
-- 3.4 파라미터화된 수수료율로 Profit 계산 (상수 하드코딩 없음)
-- ---------------------------------------------------------------------------
-- Profit = Spending * takeRateClick + Revenue * takeRateConv
-- 모든 비율과 스케일을 cube_params에서 주입.
WITH
    (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale')         AS SCALE,
    (SELECT value FROM ad_analytics.cube_params WHERE name = 'takeRateClick') AS takeClick,
    (SELECT value FROM ad_analytics.cube_params WHERE name = 'takeRateConv')  AS takeConv
SELECT
    campaignGoal,
    round(sumIf(winPrice, eventType = 'CLICK') / SCALE, 2)              AS spending,
    round(sumIf(conversionValue,
                eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) / SCALE, 2) AS revenue,
    round(sumIf(winPrice, eventType = 'CLICK') / SCALE * takeClick
        + sumIf(conversionValue,
                eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) / SCALE * takeConv, 2) AS profit
FROM   ad_analytics.ad_events
GROUP  BY campaignGoal
ORDER  BY profit DESC;

-- ---------------------------------------------------------------------------
-- 3.5 Time-series slice — daily KPIs (date partition pruning + ORDER BY)
-- 3.5 시계열 슬라이스 — 일별 KPI (날짜 파티션 프루닝 + ORDER BY)
-- ---------------------------------------------------------------------------
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    toDate(eventTs)                                                     AS day,
    countIf(eventType = 'IMPRESSION')                                   AS impressions,
    countIf(eventType = 'CLICK')                                        AS clicks,
    round(sumIf(winPrice, eventType = 'CLICK') / SCALE, 2)              AS spending,
    round(sumIf(conversionValue,
                eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) / SCALE, 2) AS revenue
FROM   ad_analytics.ad_events
WHERE  eventTs >= '2026-06-01'
GROUP  BY day
ORDER  BY day;

SELECT 'Step 3 complete — the cube responds to arbitrary GROUP BY.' AS done;
