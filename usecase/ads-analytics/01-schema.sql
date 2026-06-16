-- ============================================================================
-- ads-analytics Step 1: Schema (Ad Event Cube + Campaign Dictionary + Params)
-- ads-analytics 1단계: 스키마 (광고 이벤트 큐브 + 캠페인 사전 + 파라미터)
-- ============================================================================
-- Scenario: A generic digital advertising platform (ad network / retail media /
--           DSP-SSP / in-house ad server) records bid telemetry, ML ranking
--           signals, and business KPIs into ONE wide append-only event row, and
--           wants to slice it by arbitrary dimensions in near real time.
--           => the classic OLAP "cube" workload.
-- 시나리오: 디지털 광고 플랫폼(애드 네트워크 / 리테일 미디어 / DSP·SSP / 인하우스
--           광고 서버)이 입찰 텔레메트리 + ML 랭킹 신호 + 비즈니스 KPI를 하나의
--           넓은 append-only 이벤트 row에 기록하고, 임의 차원으로 거의 실시간
--           집계하기를 원함. => 전형적인 OLAP "큐브" 워크로드.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS ad_analytics;

-- ============================================================================
-- 1.1 ad_events — the single wide event table (denormalized cube source)
-- 1.1 ad_events — 단일 와이드 이벤트 테이블 (비정규화 큐브 소스)
-- ============================================================================
-- Money fields are stored as scaled integers (micro-units, SCALE = 1,000,000)
-- to avoid float drift:  currency = stored / 1,000,000.
-- 금액 필드는 부동소수점 오차를 피하기 위해 scaled integer(마이크로 단위,
-- SCALE = 1,000,000)로 저장:  통화값 = 저장값 / 1,000,000.
--
-- ORDER BY puts the most common filter/group dimensions first so that
-- partition pruning + sort locality + the primary index all help cube queries.
-- ORDER BY는 가장 빈번한 필터/그룹 차원을 앞에 두어 파티션 프루닝 + 정렬 지역성
-- + 기본 인덱스가 모두 큐브 쿼리를 돕도록 함.
-- ============================================================================

DROP TABLE IF EXISTS ad_analytics.ad_events;
CREATE TABLE ad_analytics.ad_events
(
    -- ---- Time / 시간 ---------------------------------------------------------
    eventTs            DateTime,
    requestTs          DateTime,

    -- ---- Ad object hierarchy L1..L4 / 광고 객체 계층 L1~L4 -------------------
    accountId          String,                    -- L1
    campaignId         String,                    -- L2
    lineItemId         String,                    -- L3
    creativeId         String,                    -- L4
    creativeFormat     LowCardinality(String),    -- image / video / native ...
    renderFormat       LowCardinality(String),    -- banner / interstitial / native
    campaignGoal       LowCardinality(String),    -- awareness / consideration / conversion

    -- ---- Inventory / supply / 인벤토리·매체 ---------------------------------
    inventoryId        String,
    publisherId        String,
    supplyId           String,
    channelType        LowCardinality(String),    -- app / web / ctv
    placementId        String,
    billingType        LowCardinality(String),    -- CPC / CPM / CPA

    -- ---- User / device / 사용자·디바이스 ------------------------------------
    userId             Nullable(String),          -- logged-in user (high cardinality)
    deviceId           String,                    -- normalized device id
    advertisingId      String,                    -- IDFA / GAID
    sessionId          String,
    platform           LowCardinality(String),    -- iOS / Android / Web
    platformVersion    String,

    -- ---- Event / 이벤트 -----------------------------------------------------
    eventType          LowCardinality(String),    -- IMPRESSION / CLICK / *_CONVERSION ...
    interactionSubType LowCardinality(String),    -- detail / expand / save ... (for INTERACTION)
    validStatus        LowCardinality(String),    -- valid / invalid / abuse
    billingStatus      LowCardinality(String),    -- billable / non_billable / hold
    isRetargeting      UInt8,
    isAudienceSegment  UInt8,

    -- ---- Bidding / RTB / 입찰 -----------------------------------------------
    requestId          String,                    -- bid request id (high cardinality)
    rank               Int32,                     -- final served rank
    candidateRank      Int32,                     -- pre-auction candidate rank
    candidateSource    LowCardinality(String),
    responseCount      Int32,

    -- ---- Money (scaled integers) / 금액 (scaled integer) --------------------
    bidPrice           Int64,
    winPrice           Int64,
    conversionValue    Int64,

    -- ---- ML ranking signals / ML 랭킹 신호 ----------------------------------
    rawPCtr            Float64,
    rawPctcvr          Float64,
    rawQualityScore    Float64,
    qualityScore       Float64,                   -- after capping
    cappedScore        Float64,

    -- ---- Semi-structured JSON / 반정형 JSON ---------------------------------
    creativeAsset      String,                    -- {assetId, imageUrl, item:{id,name}}
    biddingStrategy    String,                    -- {type, cpc, troas}
    experiment         String                     -- {demand:{...}, supply:{...}}
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(eventTs)
ORDER BY  (channelType, campaignId, eventType, eventTs)
SETTINGS  index_granularity = 8192;

-- ============================================================================
-- 1.2 campaign_meta — small dimension table feeding the dictionary
-- 1.2 campaign_meta — 사전(Dictionary)의 소스가 되는 작은 차원 테이블
-- ============================================================================
-- A typical enrichment pattern: keep campaign metadata in a small table, then
-- expose it as an in-memory DICTIONARY so cube queries do dictGet() instead of
-- paying a JOIN on every request.
-- 전형적인 enrichment 패턴: 캠페인 메타를 작은 테이블에 두고, 인메모리
-- DICTIONARY로 올려 매 쿼리 JOIN 대신 dictGet() 룩업으로 처리.
-- ============================================================================

DROP TABLE IF EXISTS ad_analytics.campaign_meta;
CREATE TABLE ad_analytics.campaign_meta
(
    campaignId  String,
    name        String,
    status      LowCardinality(String),
    targetRoas  Float64,
    createdAt   DateTime,
    endAt       DateTime
)
ENGINE = MergeTree
ORDER BY campaignId;

-- ============================================================================
-- 1.3 campaign_dict — in-memory dictionary over campaign_meta
-- 1.3 campaign_dict — campaign_meta 위에 올린 인메모리 사전
-- ============================================================================
-- LIFETIME(MIN..MAX) controls how often ClickHouse reloads the source.
-- HASHED layout keeps the whole dimension in RAM for O(1) dictGet().
-- LIFETIME(MIN..MAX)으로 소스 리로드 주기를 제어. HASHED 레이아웃은 차원 전체를
-- RAM에 올려 dictGet()을 O(1)로 만듦.
-- ============================================================================

DROP DICTIONARY IF EXISTS ad_analytics.campaign_dict;
CREATE DICTIONARY ad_analytics.campaign_dict
(
    campaignId  String,
    name        String,
    status      String,
    targetRoas  Float64,
    createdAt   DateTime,
    endAt       DateTime
)
PRIMARY KEY campaignId
SOURCE(CLICKHOUSE(TABLE 'campaign_meta' DB 'ad_analytics'))
LAYOUT(COMPLEX_KEY_HASHED())
LIFETIME(MIN 300 MAX 600);

-- ============================================================================
-- 1.4 cube_params — runtime parameters (SCALE, take rates) kept OUT of code
-- 1.4 cube_params — 런타임 파라미터 (SCALE, 수수료율)를 코드 밖으로 분리
-- ============================================================================
-- Never hard-code scale factors or take rates in measure expressions; read them
-- from a parameter table so contract/model changes do not require query edits.
-- 스케일 팩터·수수료율을 지표 표현식에 하드코딩하지 말고 파라미터 테이블에서 읽기.
-- 계약/모델 변경 시 쿼리를 고치지 않아도 됨.
-- ============================================================================

DROP TABLE IF EXISTS ad_analytics.cube_params;
CREATE TABLE ad_analytics.cube_params
(
    name   String,
    value  Float64
)
ENGINE = MergeTree
ORDER BY name;

INSERT INTO ad_analytics.cube_params VALUES
    ('scale',          1000000.0),   -- micro-unit scale factor
    ('takeRateClick',  0.15),        -- platform take rate on click spend
    ('takeRateConv',   0.05);        -- platform take rate on conversion revenue

SELECT 'Schema created. Tables & dictionaries:' AS message;
SELECT name, engine
FROM   system.tables
WHERE  database = 'ad_analytics'
ORDER  BY name;
