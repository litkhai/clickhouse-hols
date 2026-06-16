-- ============================================================================
-- ads-analytics Step 5: Semi-Structured JSON + Dictionary Enrichment
-- ads-analytics 5단계: 반정형 JSON + 사전(Dictionary) Enrichment
-- ============================================================================
-- Two enrichment patterns that keep the wide table queryable without JOINs:
--   1) JSONExtract* on String columns (creativeAsset / biddingStrategy / experiment)
--   2) dictGet() on campaign_dict for in-memory campaign metadata lookup
-- 와이드 테이블을 JOIN 없이 쿼리 가능하게 하는 두 enrichment 패턴:
--   1) String 컬럼에 JSONExtract* (creativeAsset / biddingStrategy / experiment)
--   2) campaign_dict에 dictGet()으로 인메모리 캠페인 메타 룩업
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 5.1 Parse the creativeAsset JSON — nested paths
-- 5.1 creativeAsset JSON 파싱 — 중첩 경로
-- ---------------------------------------------------------------------------
-- JSONExtractString(col, 'a', 'b') walks nested keys (col.a.b).
-- JSONExtractString(col, 'a', 'b')는 중첩 키(col.a.b)를 따라감.

SELECT
    JSONExtractString(creativeAsset, 'assetId')                        AS asset_id,
    JSONExtractString(creativeAsset, 'item', 'id')                     AS item_id,
    JSONExtractString(creativeAsset, 'item', 'name')                   AS item_name,
    count()                                                            AS impressions,
    round(countIf(eventType = 'CLICK') * 100.0
          / nullIf(countIf(eventType = 'IMPRESSION'), 0), 3)           AS ctr_pct
FROM   ad_analytics.ad_events
GROUP  BY asset_id, item_id, item_name
ORDER  BY impressions DESC
LIMIT  10;

-- ---------------------------------------------------------------------------
-- 5.2 Bidding strategy JSON — typed extraction + numeric parse
-- 5.2 입찰 전략 JSON — 타입 추출 + 숫자 파싱
-- ---------------------------------------------------------------------------
-- JSONExtractFloat parses numbers; combine with the SCALE param for currency.
-- JSONExtractFloat는 숫자를 파싱; SCALE 파라미터와 결합해 통화 단위로 변환.
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    JSONExtractString(biddingStrategy, 'type')                         AS strategy_type,
    count()                                                            AS events,
    round(avg(JSONExtractFloat(biddingStrategy, 'cpc')) / SCALE, 4)    AS avg_fixed_cpc,
    round(avg(JSONExtractFloat(biddingStrategy, 'troas')), 1)          AS avg_target_roas,
    -- share of impressions running TARGET_ROAS
    -- TARGET_ROAS로 운영되는 노출 비율
    round(countIf(eventType = 'IMPRESSION'
                  AND JSONExtractString(biddingStrategy, 'type') = 'TARGET_ROAS') * 100.0
          / nullIf(countIf(eventType = 'IMPRESSION'), 0), 2)           AS troas_imp_share_pct
FROM   ad_analytics.ad_events
GROUP  BY strategy_type
ORDER  BY events DESC;

-- ---------------------------------------------------------------------------
-- 5.3 A/B experiment framework — demand-side vs supply-side groups
-- 5.3 A/B 실험 프레임워크 — 수요측 vs 공급측 그룹
-- ---------------------------------------------------------------------------
-- Generalize multi-stage experiments into demand/supply experiment dimensions.
-- 다단계 실험을 수요/공급 실험 차원으로 일반화.
SELECT
    JSONExtractString(experiment, 'demand', 'group')                   AS demand_group,
    JSONExtractString(experiment, 'supply', 'group')                   AS supply_group,
    countIf(eventType = 'IMPRESSION')                                  AS impressions,
    round(countIf(eventType = 'CLICK') * 100.0
          / nullIf(countIf(eventType = 'IMPRESSION'), 0), 4)           AS ctr_pct,
    round(countIf(eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) * 100.0
          / nullIf(countIf(eventType = 'CLICK'), 0), 4)                AS cvr_pct
FROM   ad_analytics.ad_events
GROUP  BY demand_group, supply_group
ORDER  BY demand_group, supply_group;

-- ---------------------------------------------------------------------------
-- 5.4 Dictionary enrichment — dictGet() instead of a JOIN
-- 5.4 사전 Enrichment — JOIN 대신 dictGet()
-- ---------------------------------------------------------------------------
-- campaign_dict (HASHED, in RAM) resolves campaign metadata per row with no JOIN.
-- campaign_dict(HASHED, RAM)가 JOIN 없이 행마다 캠페인 메타를 해결.
WITH (SELECT value FROM ad_analytics.cube_params WHERE name = 'scale') AS SCALE
SELECT
    campaignId,
    dictGet('ad_analytics.campaign_dict', 'name',       campaignId)    AS campaign_name,
    dictGet('ad_analytics.campaign_dict', 'status',     campaignId)    AS status,
    dictGetFloat64('ad_analytics.campaign_dict', 'targetRoas', tuple(campaignId)) AS target_roas,
    round(sumIf(conversionValue,
                eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION')) * 100.0
          / nullIf(sumIf(winPrice, eventType = 'CLICK'), 0), 1)        AS actual_roas_pct
FROM   ad_analytics.ad_events
GROUP  BY campaignId
HAVING status = 'active'
ORDER  BY actual_roas_pct DESC
LIMIT  10;

-- "Pacing": actual ROAS vs the campaign's target ROAS, only for active campaigns.
-- "페이싱": 활성 캠페인에 대해 실제 ROAS vs 목표 ROAS 비교.

-- ---------------------------------------------------------------------------
-- 5.5 Promote a hot JSON path to a MATERIALIZED column
-- 5.5 핫한 JSON 경로를 MATERIALIZED 컬럼으로 승격
-- ---------------------------------------------------------------------------
-- If a JSON path is parsed on every query, materialize it once: the value is
-- computed at INSERT (and MATERIALIZE COLUMN backfills existing parts) so reads
-- scan a plain column instead of re-parsing JSON.
-- 매 쿼리마다 파싱되는 JSON 경로는 한 번 materialize: INSERT 시점에 계산되고
-- (MATERIALIZE COLUMN으로 기존 파트 백필) 읽을 때 JSON 재파싱 없이 일반 컬럼만 스캔.

ALTER TABLE ad_analytics.ad_events
    ADD COLUMN IF NOT EXISTS biddingType LowCardinality(String)
    MATERIALIZED JSONExtractString(biddingStrategy, 'type');

-- Backfill existing parts (new INSERTs fill it automatically).
-- 기존 파트 백필 (새 INSERT는 자동으로 채워짐).
ALTER TABLE ad_analytics.ad_events MATERIALIZE COLUMN biddingType;

-- Now this scans a LowCardinality column, not the JSON string.
-- 이제 JSON 문자열이 아니라 LowCardinality 컬럼을 스캔.
SELECT biddingType, count() AS events
FROM   ad_analytics.ad_events
GROUP  BY biddingType
ORDER  BY events DESC;

SELECT 'Step 5 complete — JSON + dictGet enrich the cube without JOINs.' AS done;
