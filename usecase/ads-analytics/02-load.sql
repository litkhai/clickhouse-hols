-- ============================================================================
-- ads-analytics Step 2: Load Campaign Meta + 10,000,000 Synthetic Ad Events
-- ads-analytics 2단계: 캠페인 메타 + 1,000만 건의 합성 광고 이벤트 적재
-- ============================================================================
-- Funnel design (per-row independent sampling, hashed from `number`):
--   IMPRESSION 85%  VIEWABLE_IMPRESSION 8%  CLICK 3.5%  INTERACTION 1.5%
--   DIRECT_CONVERSION 1.2%  INDIRECT_CONVERSION 0.8%
--   => CTR ~ click/impression, CVR ~ conv/click come out realistically small.
--   winPrice is meaningful on CLICK rows; conversionValue on *_CONVERSION rows.
-- 퍼널 설계 (`number` 해시 기반 행별 독립 샘플링):
--   노출 85% / 뷰어블 8% / 클릭 3.5% / 인터랙션 1.5% / 직접전환 1.2% / 간접전환 0.8%
--   => CTR(클릭/노출), CVR(전환/클릭)이 현실적으로 작게 나옴.
--   winPrice는 CLICK 행에서, conversionValue는 *_CONVERSION 행에서 의미를 가짐.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 2.1 Campaign metadata — 500 campaigns feeding campaign_dict
-- 2.1 캠페인 메타데이터 — campaign_dict의 소스가 되는 500개 캠페인
-- ---------------------------------------------------------------------------

TRUNCATE TABLE ad_analytics.campaign_meta;

INSERT INTO ad_analytics.campaign_meta
SELECT
    concat('camp_', toString(number))                              AS campaignId,
    concat('Campaign ', toString(number))                         AS name,
    arrayElement(['active', 'active', 'active', 'paused', 'ended'],
                 1 + (cityHash64(number, 'status') % 5))           AS status,
    -- target ROAS as a percentage, 150% .. 500%
    150.0 + (cityHash64(number, 'troas') % 350)                    AS targetRoas,
    toDateTime('2026-01-01 00:00:00')
        + toIntervalDay(cityHash64(number, 'created') % 120)       AS createdAt,
    toDateTime('2026-07-01 00:00:00')
        + toIntervalDay(cityHash64(number, 'end') % 180)           AS endAt
FROM numbers(500);

SELECT 'Loaded campaigns:' AS label, count() AS rows FROM ad_analytics.campaign_meta;

-- ---------------------------------------------------------------------------
-- 2.2 The 10M-row event stream
-- 2.2 1,000만 건 이벤트 스트림
-- ---------------------------------------------------------------------------

TRUNCATE TABLE ad_analytics.ad_events;

INSERT INTO ad_analytics.ad_events
WITH
    -- event type bucket 0..999 -> funnel stage
    -- 이벤트 타입 버킷 0..999 -> 퍼널 단계
    (cityHash64(number, 'etype') % 1000)                           AS et,
    multiIf(
        et < 850, 'IMPRESSION',
        et < 930, 'VIEWABLE_IMPRESSION',
        et < 965, 'CLICK',
        et < 980, 'INTERACTION',
        et < 992, 'DIRECT_CONVERSION',
                  'INDIRECT_CONVERSION')                           AS _eventType,
    (_eventType = 'CLICK')                                         AS _isClick,
    (_eventType IN ('DIRECT_CONVERSION', 'INDIRECT_CONVERSION'))   AS _isConv,

    -- base bid price in micro-units: 0.10 .. 2.10
    -- 마이크로 단위 기본 입찰가: 0.10 .. 2.10
    toInt64(100000 + (cityHash64(number, 'bid') % 2000000))        AS _bidPrice,

    -- small ids reused across JSON payloads
    -- JSON 페이로드에서 재사용되는 작은 id 들
    (cityHash64(number, 'asset') % 50000)                          AS _assetId,
    (cityHash64(number, 'item')  % 20000)                          AS _itemId,
    (cityHash64(number, 'dx')    % 40)                             AS _dxId,
    (cityHash64(number, 'sx')    % 25)                             AS _sxId,
    (cityHash64(number, 'bstrat') % 2)                             AS _bstrat,
    (1000000 + cityHash64(number, 'cpc') % 1500000)               AS _fixedCpc,
    (200.0 + (cityHash64(number, 'jtroas') % 300))                 AS _jTroas,
    -- raw quality score, deterministic from the hash so it can be referenced
    -- by both the column and the capping logic below
    -- 해시 기반 결정적 raw 품질 점수 (컬럼과 아래 캡핑 로직 모두에서 참조)
    ((cityHash64(number, 'rq') % 10000) / 10000.0)                 AS _rawQ
SELECT
    -- ---- Time / 시간 -------------------------------------------------------
    toDateTime('2026-05-15 00:00:00')
        + toIntervalSecond(cityHash64(number, 'ts') % toUInt64(30 * 86400)) AS eventTs,
    eventTs - toIntervalSecond(1 + cityHash64(number, 'reqlag') % 5)        AS requestTs,

    -- ---- Ad object hierarchy / 광고 객체 계층 ------------------------------
    concat('acc_',  toString(cityHash64(number, 'acc')  % 50))     AS accountId,
    concat('camp_', toString(cityHash64(number, 'camp') % 500))    AS campaignId,
    concat('li_',   toString(cityHash64(number, 'li')   % 3000))   AS lineItemId,
    concat('cr_',   toString(cityHash64(number, 'cr')   % 8000))   AS creativeId,
    arrayElement(['image', 'video', 'native'],
                 1 + (cityHash64(number, 'cfmt') % 3))             AS creativeFormat,
    arrayElement(['banner', 'interstitial', 'native', 'video'],
                 1 + (cityHash64(number, 'rfmt') % 4))             AS renderFormat,
    arrayElement(['awareness', 'consideration', 'conversion'],
                 1 + (cityHash64(number, 'goal') % 3))             AS campaignGoal,

    -- ---- Inventory / supply / 인벤토리·매체 -------------------------------
    concat('inv_', toString(cityHash64(number, 'inv') % 4000))     AS inventoryId,
    concat('pub_', toString(cityHash64(number, 'pub') % 300))      AS publisherId,
    concat('sup_', toString(cityHash64(number, 'sup') % 40))       AS supplyId,
    arrayElement(['app', 'web', 'ctv'],
                 1 + (cityHash64(number, 'chan') % 3))             AS channelType,
    concat('plc_', toString(cityHash64(number, 'plc') % 6000))     AS placementId,
    arrayElement(['CPC', 'CPM', 'CPA'],
                 1 + (cityHash64(number, 'bill') % 3))             AS billingType,

    -- ---- User / device / 사용자·디바이스 ----------------------------------
    -- 70% logged in, else NULL  /  70%는 로그인, 나머지는 NULL
    if(cityHash64(number, 'login') % 10 < 7,
       concat('u_', toString(cityHash64(number, 'uid') % 2000000)),
       NULL)                                                       AS userId,
    concat('d_',   toString(cityHash64(number, 'did') % 3000000))  AS deviceId,
    concat('adid_', toString(cityHash64(number, 'adid') % 3000000)) AS advertisingId,
    concat('sess_', toString(cityHash64(number, 'sess') % 5000000)) AS sessionId,
    arrayElement(['iOS', 'Android', 'Web'],
                 1 + (cityHash64(number, 'plat') % 3))             AS platform,
    arrayElement(['14.0', '15.2', '16.1', '17.4', '13.0'],
                 1 + (cityHash64(number, 'pver') % 5))             AS platformVersion,

    -- ---- Event / 이벤트 ----------------------------------------------------
    _eventType                                                     AS eventType,
    if(_eventType = 'INTERACTION',
       arrayElement(['detail', 'expand', 'save', 'cta'],
                    1 + (cityHash64(number, 'isub') % 4)),
       '')                                                         AS interactionSubType,
    arrayElement(['valid', 'valid', 'valid', 'invalid', 'abuse'],
                 1 + (cityHash64(number, 'valid') % 5))            AS validStatus,
    arrayElement(['billable', 'billable', 'non_billable', 'hold'],
                 1 + (cityHash64(number, 'bstat') % 4))            AS billingStatus,
    toUInt8(cityHash64(number, 'retgt') % 10 < 3)                  AS isRetargeting,
    toUInt8(cityHash64(number, 'aud')   % 10 < 4)                  AS isAudienceSegment,

    -- ---- Bidding / RTB / 입찰 ----------------------------------------------
    -- ~2 events per bid request  /  요청당 약 2개 이벤트
    concat('req_', toString(intDiv(number, 2)))                    AS requestId,
    toInt32(1 + cityHash64(number, 'rank') % 10)                   AS rank,
    toInt32(rank + cityHash64(number, 'crank') % 5)               AS candidateRank,
    arrayElement(['retrieval', 'broad_match', 'retarget', 'lookalike'],
                 1 + (cityHash64(number, 'csrc') % 4))             AS candidateSource,
    toInt32(1 + cityHash64(number, 'resp') % 20)                   AS responseCount,

    -- ---- Money (scaled integers) / 금액 ------------------------------------
    _bidPrice                                                      AS bidPrice,
    if(_isClick, intDiv(_bidPrice * 8, 10), toInt64(0))           AS winPrice,
    if(_isConv,
       toInt64(5000000 + cityHash64(number, 'cval') % 95000000),
       toInt64(0))                                                 AS conversionValue,

    -- ---- ML ranking signals / ML 랭킹 신호 --------------------------------
    0.005 + (cityHash64(number, 'pctr') % 2000) / 10000.0          AS rawPCtr,
    0.001 + (cityHash64(number, 'pcvr') % 500)  / 10000.0          AS rawPctcvr,
    _rawQ                                                          AS rawQualityScore,
    -- qualityScore = rawQualityScore after capping: ~20% lower-capped,
    --                ~15% higher-capped, rest identity
    -- qualityScore = 캡핑 후 점수: ~20% 하향, ~15% 상향, 나머지는 동일
    multiIf(
        cityHash64(number, 'cap') % 100 < 20, round(_rawQ * 0.85, 4),
        cityHash64(number, 'cap') % 100 < 35, least(round(_rawQ * 1.15, 4), 1.0),
        _rawQ)                                                     AS qualityScore,
    least(0.005 + (cityHash64(number, 'pctr') % 2000) / 10000.0, 0.15) AS cappedScore,

    -- ---- Semi-structured JSON / 반정형 JSON --------------------------------
    concat('{"assetId":"as_', toString(_assetId),
           '","imageUrl":"https://cdn.example.com/', toString(_assetId),
           '.jpg","item":{"id":"item_', toString(_itemId),
           '","name":"Item ', toString(_itemId), '"}}')            AS creativeAsset,
    if(_bstrat = 0,
       concat('{"type":"FIXED_CPC","cpc":', toString(_fixedCpc), '}'),
       concat('{"type":"TARGET_ROAS","troas":', toString(_jTroas), '}')) AS biddingStrategy,
    concat('{"demand":{"id":"dx_', toString(_dxId),
           '","group":"', if(cityHash64(number, 'dg') % 2 = 0, 'control', 'treatment'),
           '","version":"v', toString(1 + cityHash64(number, 'dv') % 3),
           '"},"supply":{"id":"sx_', toString(_sxId),
           '","group":"', if(cityHash64(number, 'sg') % 2 = 0, 'control', 'treatment'),
           '","version":"v', toString(1 + cityHash64(number, 'sv') % 3),
           '"}}')                                                  AS experiment
FROM numbers(10000000)
SETTINGS max_insert_threads = 4, max_block_size = 100000;

-- ============================================================================
-- Confirm load / 적재 확인
-- ============================================================================

SELECT 'Loaded events:' AS label, count() AS rows FROM ad_analytics.ad_events;

SELECT 'Event funnel:' AS label,
       eventType,
       count()                                  AS events,
       round(count() * 100.0 / sum(count()) OVER (), 2) AS pct
FROM   ad_analytics.ad_events
GROUP  BY eventType
ORDER  BY events DESC;

SELECT 'Date range:' AS label,
       toString(min(eventTs)) AS first_event,
       toString(max(eventTs)) AS last_event
FROM   ad_analytics.ad_events;

SELECT 'Cardinality (approx):' AS label,
       uniq(campaignId)  AS campaigns,
       uniq(userId)      AS users,
       uniq(deviceId)    AS devices,
       uniq(requestId)   AS requests
FROM   ad_analytics.ad_events;
