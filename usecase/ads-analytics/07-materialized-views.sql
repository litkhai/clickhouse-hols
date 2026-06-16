-- ============================================================================
-- ads-analytics Step 7: Pre-Aggregation with Materialized Views
-- ads-analytics 7단계: Materialized View로 사전 집계
-- ============================================================================
-- Reporting dashboards repeat the same daily roll-ups. Pre-aggregate them into
-- an AggregatingMergeTree via a Materialized View so dashboard queries read a
-- few thousand rows instead of 10M. uniqState keeps approximate-distinct state
-- in a *mergeable* form.
-- 리포팅 대시보드는 동일한 일별 롤업을 반복함. AggregatingMergeTree + MV로 미리
-- 집계하면 대시보드 쿼리가 1,000만 행 대신 수천 행만 읽음. uniqState는 근사
-- distinct 상태를 *합산 가능한* 형태로 보존.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 7.1 Target table — daily cube per (campaign, event type)
-- 7.1 타겟 테이블 — (캠페인, 이벤트타입)별 일별 큐브
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS ad_analytics.daily_campaign_cube;
CREATE TABLE ad_analytics.daily_campaign_cube
(
    reportDate    Date,
    campaignId    String,
    eventType     LowCardinality(String),
    events        AggregateFunction(count),
    spend_raw     AggregateFunction(sum, Int64),   -- winPrice (scaled int)
    conv_value    AggregateFunction(sum, Int64),   -- conversionValue (scaled int)
    users         AggregateFunction(uniq, Nullable(String))
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(reportDate)
ORDER BY (reportDate, campaignId, eventType);

-- ---------------------------------------------------------------------------
-- 7.2 Materialized View — roll up every NEW insert automatically
-- 7.2 Materialized View — 새 INSERT를 자동으로 롤업
-- ---------------------------------------------------------------------------

DROP VIEW IF EXISTS ad_analytics.daily_campaign_cube_mv;
CREATE MATERIALIZED VIEW ad_analytics.daily_campaign_cube_mv
TO ad_analytics.daily_campaign_cube
AS
SELECT
    toDate(eventTs)         AS reportDate,
    campaignId,
    eventType,
    countState()            AS events,
    sumState(winPrice)      AS spend_raw,
    sumState(conversionValue) AS conv_value,
    uniqState(userId)       AS users
FROM   ad_analytics.ad_events
GROUP  BY reportDate, campaignId, eventType;

-- ---------------------------------------------------------------------------
-- 7.3 Backfill from existing data (the MV only catches NEW inserts)
-- 7.3 기존 데이터 백필 (MV는 새 INSERT만 잡음)
-- ---------------------------------------------------------------------------

INSERT INTO ad_analytics.daily_campaign_cube
SELECT
    toDate(eventTs)         AS reportDate,
    campaignId,
    eventType,
    countState()            AS events,
    sumState(winPrice)      AS spend_raw,
    sumState(conversionValue) AS conv_value,
    uniqState(userId)       AS users
FROM   ad_analytics.ad_events
GROUP  BY reportDate, campaignId, eventType;

SELECT 'Pre-aggregated rows:' AS label, count() AS rows
FROM   ad_analytics.daily_campaign_cube;

-- ---------------------------------------------------------------------------
-- 7.4 Query the aggregate — *Merge functions reconstruct the metrics
-- 7.4 집계 조회 — *Merge 함수로 지표 복원
-- ---------------------------------------------------------------------------
-- Aggregate-state columns are read with the *Merge sibling of the *State used.
-- *State로 저장한 컬럼은 같은 이름의 *Merge 함수로 읽음.
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    campaignId,
    countMergeIf(events, eventType = 'IMPRESSION')                     AS impressions,
    countMergeIf(events, eventType = 'CLICK')                          AS clicks,
    round(sumMergeIf(spend_raw, eventType = 'CLICK') / SCALE, 2)       AS spending,
    round(sumMergeIf(conv_value,
                     eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) / SCALE, 2) AS revenue,
    uniqMerge(users)                                                   AS reach
FROM   ad_analytics.daily_campaign_cube
GROUP  BY campaignId
ORDER  BY spending DESC
LIMIT  10;

-- ---------------------------------------------------------------------------
-- 7.5 Performance: same answer, aggregate vs raw scan
-- 7.5 성능: 동일 결과를 집계 테이블 vs 원본 스캔으로
-- ---------------------------------------------------------------------------
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT * FROM (
    SELECT 'from_aggregate' AS source,
           countMergeIf(events, eventType = 'CLICK')                   AS total_clicks,
           round(sumMergeIf(spend_raw, eventType = 'CLICK') / SCALE, 2) AS total_spend
    FROM   ad_analytics.daily_campaign_cube
    UNION ALL
    SELECT 'from_raw_events' AS source,
           countIf(eventType = 'CLICK'),
           round(sumIf(winPrice, eventType = 'CLICK') / SCALE, 2)
    FROM   ad_analytics.ad_events
)
ORDER BY source;

-- ---------------------------------------------------------------------------
-- 7.6 Live-insert test — the MV picks up brand-new events
-- 7.6 라이브 INSERT 테스트 — MV가 새 이벤트를 자동 집계하는지 확인
-- ---------------------------------------------------------------------------
-- Insert 1,000 fresh clicks for camp_0 on a brand-new date. Note: the
-- MATERIALIZED biddingType column is omitted from the column list (computed).
-- 새 날짜에 camp_0용 클릭 1,000건 INSERT. MATERIALIZED biddingType 컬럼은
-- 컬럼 리스트에서 제외(자동 계산).

INSERT INTO ad_analytics.ad_events
    (eventTs, requestTs, accountId, campaignId, lineItemId, creativeId,
     creativeFormat, renderFormat, campaignGoal, inventoryId, publisherId,
     supplyId, channelType, placementId, billingType, userId, deviceId,
     advertisingId, sessionId, platform, platformVersion, eventType,
     interactionSubType, validStatus, billingStatus, isRetargeting,
     isAudienceSegment, requestId, rank, candidateRank, candidateSource,
     responseCount, bidPrice, winPrice, conversionValue, rawPCtr, rawPctcvr,
     rawQualityScore, qualityScore, cappedScore, creativeAsset,
     biddingStrategy, experiment)
SELECT
    toDateTime('2026-06-20 12:00:00') + toIntervalSecond(number) AS eventTs,
    eventTs - toIntervalSecond(2)                                AS requestTs,
    'acc_0', 'camp_0', 'li_0', 'cr_0',
    'image', 'banner', 'conversion',
    'inv_0', 'pub_0', 'sup_0', 'app', 'plc_0', 'CPC',
    concat('u_live_', toString(number)), 'd_live', 'adid_live', 'sess_live',
    'iOS', '17.4', 'CLICK', '', 'valid', 'billable', 0, 1,
    concat('req_live_', toString(number)), 1, 1, 'retrieval', 5,
    toInt64(500000), toInt64(400000), toInt64(0),
    0.05, 0.01, 0.5, 0.5, 0.05,
    '{"assetId":"as_0","imageUrl":"https://cdn.example.com/0.jpg","item":{"id":"item_0","name":"Item 0"}}',
    '{"type":"FIXED_CPC","cpc":500000}',
    '{"demand":{"id":"dx_0","group":"control","version":"v1"},"supply":{"id":"sx_0","group":"control","version":"v1"}}'
FROM numbers(1000);

-- The aggregate table now has a row for 2026-06-20 / camp_0 / CLICK.
-- 집계 테이블에 2026-06-20 / camp_0 / CLICK 행이 자동 생성됨.
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    reportDate,
    campaignId,
    countMerge(events)                       AS clicks,
    round(sumMerge(spend_raw) / SCALE, 2)    AS spending,
    uniqMerge(users)                         AS reach
FROM   ad_analytics.daily_campaign_cube
WHERE  reportDate = '2026-06-20' AND campaignId = 'camp_0' AND eventType = 'CLICK'
GROUP  BY reportDate, campaignId;

SELECT 'Step 7 complete. Lab finished. To clean up: source 99-cleanup.sql' AS done;
