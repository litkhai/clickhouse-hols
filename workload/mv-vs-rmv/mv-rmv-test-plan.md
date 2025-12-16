# MV vs RMV 리소스 효율성 비교 테스트

## 1. 테스트 가설

**가설**: RMV(5분 주기 배치)가 MV(실시간)보다 리소스 효율성이 높을 것이다.

**이론적 근거**:
- **MV (Materialized View)**: INSERT 시점마다 즉시 트리거되어 개별 row/block 단위로 aggregation 수행. 매 INSERT마다 새로운 part 생성 → 잦은 merge 발생
- **RMV (Refreshable Materialized View)**: 5분치 데이터를 한번에 처리. 배치 처리로 인한 I/O 최적화, 적은 part 수, 효율적인 merge

**예상 결과**:
| 메트릭 | MV (실시간) | RMV (5분 배치) |
|--------|------------|---------------|
| CPU 사용량 | 높음 (지속적) | 낮음 (간헐적 스파이크) |
| Memory Peak | 낮지만 지속적 | 높지만 간헐적 |
| Disk I/O | 많음 (잦은 write) | 적음 (배치 write) |
| Part 수 | 많음 | 적음 |
| Merge 횟수 | 많음 | 적음 |

---

## 2. 테스트 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Source Table                              │
│              events_source (MergeTree)                       │
│   - 30분간 지속적 INSERT (1초당 ~1000 rows)                  │
└─────────────────┬───────────────────────┬───────────────────┘
                  │                       │
                  ▼                       ▼
    ┌─────────────────────┐   ┌─────────────────────────┐
    │   MV (실시간)        │   │   RMV (5분 주기)         │
    │ events_mv_realtime  │   │ events_rmv_batch        │
    │ INSERT 시 즉시 실행  │   │ REFRESH EVERY 5 MINUTE  │
    └─────────────────────┘   └─────────────────────────┘
                  │                       │
                  ▼                       ▼
    ┌─────────────────────┐   ┌─────────────────────────┐
    │  Target Table       │   │   Target Table          │
    │ events_agg_mv       │   │ events_agg_rmv          │
    │ (SummingMergeTree)  │   │ (MergeTree)             │
    └─────────────────────┘   └─────────────────────────┘
```

---

## 3. 스키마 설계

### 3.1 Source Table
```sql
CREATE DATABASE IF NOT EXISTS mv_vs_rmv;

CREATE TABLE mv_vs_rmv.events_source
(
    event_time DateTime64(3) DEFAULT now64(3),
    user_id UInt32,
    event_type LowCardinality(String),
    page_url String,
    session_id UUID,
    country LowCardinality(String),
    device_type LowCardinality(String),
    revenue Decimal(10,2),
    quantity UInt16
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (event_type, user_id, event_time);
```

### 3.2 MV Target Table + MV 정의
```sql
-- MV용 Target Table (SummingMergeTree 사용)
CREATE TABLE mv_vs_rmv.events_agg_mv
(
    event_time_5min DateTime,
    event_type LowCardinality(String),
    country LowCardinality(String),
    device_type LowCardinality(String),
    event_count UInt64,
    unique_users UInt64,
    total_revenue Decimal(18,2),
    total_quantity UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMMDD(event_time_5min)
ORDER BY (event_time_5min, event_type, country, device_type);

-- Materialized View (실시간)
CREATE MATERIALIZED VIEW mv_vs_rmv.events_mv_realtime
TO mv_vs_rmv.events_agg_mv
AS SELECT
    toStartOfFiveMinutes(event_time) AS event_time_5min,
    event_type,
    country,
    device_type,
    count() AS event_count,
    uniqExact(user_id) AS unique_users,
    sum(revenue) AS total_revenue,
    sum(quantity) AS total_quantity
FROM mv_vs_rmv.events_source
GROUP BY event_time_5min, event_type, country, device_type;
```

### 3.3 RMV Target Table + RMV 정의
```sql
-- RMV용 Target Table
CREATE TABLE mv_vs_rmv.events_agg_rmv
(
    event_time_5min DateTime,
    event_type LowCardinality(String),
    country LowCardinality(String),
    device_type LowCardinality(String),
    event_count UInt64,
    unique_users UInt64,
    total_revenue Decimal(18,2),
    total_quantity UInt64
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_time_5min)
ORDER BY (event_time_5min, event_type, country, device_type);

-- Refreshable Materialized View (5분 주기)
-- APPEND 모드: 새로운 데이터만 추가
CREATE MATERIALIZED VIEW mv_vs_rmv.events_rmv_batch
REFRESH EVERY 5 MINUTE APPEND
TO mv_vs_rmv.events_agg_rmv
AS SELECT
    toStartOfFiveMinutes(event_time) AS event_time_5min,
    event_type,
    country,
    device_type,
    count() AS event_count,
    uniqExact(user_id) AS unique_users,
    sum(revenue) AS total_revenue,
    sum(quantity) AS total_quantity
FROM mv_vs_rmv.events_source
WHERE event_time >= now() - INTERVAL 6 MINUTE  -- 겹침 방지 + 안전 마진
  AND event_time < now() - INTERVAL 1 MINUTE   -- 최신 데이터 제외
GROUP BY event_time_5min, event_type, country, device_type;
```

---

## 4. 성능 모니터링 테이블

### 4.1 메트릭 수집 테이블
```sql
-- 테스트 세션 관리
CREATE TABLE mv_vs_rmv.test_sessions
(
    session_id UUID DEFAULT generateUUIDv4(),
    test_type Enum8('MV_TEST' = 1, 'RMV_TEST' = 2, 'BOTH_TEST' = 3),
    start_time DateTime64(3) DEFAULT now64(3),
    end_time Nullable(DateTime64(3)),
    description String,
    config_json String DEFAULT '{}'
)
ENGINE = MergeTree()
ORDER BY (start_time, session_id);

-- 리소스 메트릭 스냅샷 (1분마다 수집)
CREATE TABLE mv_vs_rmv.resource_metrics
(
    collected_at DateTime64(3) DEFAULT now64(3),
    session_id UUID,
    
    -- Query 메트릭
    query_count UInt64,
    query_duration_ms UInt64,
    
    -- Memory 메트릭
    memory_usage_bytes UInt64,
    peak_memory_usage_bytes UInt64,
    
    -- CPU/Processing 메트릭  
    read_rows UInt64,
    read_bytes UInt64,
    written_rows UInt64,
    written_bytes UInt64,
    
    -- Merge 관련
    merge_count UInt64,
    parts_count UInt64,
    
    -- MV/RMV 별 구분
    metric_source Enum8('MV' = 1, 'RMV' = 2, 'SOURCE' = 3, 'SYSTEM' = 4)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(collected_at)
ORDER BY (session_id, collected_at, metric_source);

-- Part 변화 추적
CREATE TABLE mv_vs_rmv.parts_history
(
    collected_at DateTime64(3) DEFAULT now64(3),
    session_id UUID,
    table_name String,
    partition String,
    part_count UInt64,
    row_count UInt64,
    bytes_on_disk UInt64,
    active_parts UInt64,
    inactive_parts UInt64
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(collected_at)
ORDER BY (session_id, table_name, collected_at);

-- Merge 활동 로그
CREATE TABLE mv_vs_rmv.merge_activity
(
    collected_at DateTime64(3) DEFAULT now64(3),
    session_id UUID,
    table_name String,
    event_type String,
    merge_duration_ms UInt64,
    rows_read UInt64,
    rows_written UInt64,
    bytes_read UInt64,
    bytes_written UInt64,
    memory_usage UInt64
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(collected_at)
ORDER BY (session_id, table_name, collected_at);
```

### 4.2 메트릭 수집 쿼리 (1분마다 실행)

```sql
-- ======================================
-- [수동 실행] 테스트 세션 시작
-- ======================================
INSERT INTO mv_vs_rmv.test_sessions (test_type, description)
VALUES ('BOTH_TEST', 'MV vs RMV 30분 비교 테스트 - Round 1');

-- 생성된 session_id 확인
SELECT session_id FROM mv_vs_rmv.test_sessions 
ORDER BY start_time DESC LIMIT 1;


-- ======================================
-- [1분마다 실행] Part 상태 수집
-- ======================================
INSERT INTO mv_vs_rmv.parts_history
SELECT
    now64(3) AS collected_at,
    '<SESSION_ID>' AS session_id,  -- 실제 session_id로 교체
    table AS table_name,
    partition,
    count() AS part_count,
    sum(rows) AS row_count,
    sum(bytes_on_disk) AS bytes_on_disk,
    countIf(active) AS active_parts,
    countIf(NOT active) AS inactive_parts
FROM system.parts
WHERE database = 'mv_vs_rmv'
  AND table IN ('events_source', 'events_agg_mv', 'events_agg_rmv')
GROUP BY table, partition;


-- ======================================
-- [1분마다 실행] Query 메트릭 수집 - MV 관련
-- ======================================
INSERT INTO mv_vs_rmv.resource_metrics
SELECT
    now64(3) AS collected_at,
    '<SESSION_ID>' AS session_id,
    count() AS query_count,
    sum(query_duration_ms) AS query_duration_ms,
    sum(memory_usage) AS memory_usage_bytes,
    max(memory_usage) AS peak_memory_usage_bytes,
    sum(read_rows) AS read_rows,
    sum(read_bytes) AS read_bytes,
    sum(written_rows) AS written_rows,
    sum(written_bytes) AS written_bytes,
    0 AS merge_count,
    0 AS parts_count,
    'MV' AS metric_source
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 MINUTE
  AND type = 'QueryFinish'
  AND query LIKE '%events_agg_mv%'
  AND query NOT LIKE '%system%';


-- ======================================
-- [1분마다 실행] Query 메트릭 수집 - RMV 관련
-- ======================================
INSERT INTO mv_vs_rmv.resource_metrics
SELECT
    now64(3) AS collected_at,
    '<SESSION_ID>' AS session_id,
    count() AS query_count,
    sum(query_duration_ms) AS query_duration_ms,
    sum(memory_usage) AS memory_usage_bytes,
    max(memory_usage) AS peak_memory_usage_bytes,
    sum(read_rows) AS read_rows,
    sum(read_bytes) AS read_bytes,
    sum(written_rows) AS written_rows,
    sum(written_bytes) AS written_bytes,
    0 AS merge_count,
    0 AS parts_count,
    'RMV' AS metric_source
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 MINUTE
  AND type = 'QueryFinish'
  AND query LIKE '%events_agg_rmv%'
  AND query NOT LIKE '%system%';


-- ======================================
-- [1분마다 실행] Merge 활동 수집
-- ======================================
INSERT INTO mv_vs_rmv.merge_activity
SELECT
    now64(3) AS collected_at,
    '<SESSION_ID>' AS session_id,
    table AS table_name,
    event_type,
    duration_ms AS merge_duration_ms,
    read_rows AS rows_read,
    written_rows AS rows_written,
    read_bytes AS bytes_read,
    written_bytes AS bytes_written,
    peak_memory_usage AS memory_usage
FROM system.part_log
WHERE database = 'mv_vs_rmv'
  AND event_time >= now() - INTERVAL 1 MINUTE
  AND event_type IN ('MergeParts', 'MergePartsStart');
```

---

## 5. 데이터 생성 스크립트

### 5.1 연속 INSERT 생성기 (Python 권장, 또는 별도 INSERT 반복)
```sql
-- 단일 배치 INSERT (1000 rows) - 반복 실행 필요
INSERT INTO mv_vs_rmv.events_source 
(user_id, event_type, page_url, session_id, country, device_type, revenue, quantity)
SELECT
    rand() % 100000 AS user_id,
    arrayElement(['pageview', 'click', 'purchase', 'signup', 'logout'], 
                 (rand() % 5) + 1) AS event_type,
    concat('/page/', toString(rand() % 1000)) AS page_url,
    generateUUIDv4() AS session_id,
    arrayElement(['KR', 'US', 'JP', 'CN', 'DE', 'FR', 'GB', 'AU'], 
                 (rand() % 8) + 1) AS country,
    arrayElement(['mobile', 'desktop', 'tablet'], 
                 (rand() % 3) + 1) AS device_type,
    round(rand() % 10000 / 100, 2) AS revenue,
    (rand() % 10) + 1 AS quantity
FROM numbers(1000);

-- 참고: 30분간 1초당 1회 실행 시 약 1,800,000 rows
```

---

## 6. 테스트 실행 절차

### Round 1: MV + RMV 동시 테스트
```
시간    작업
─────────────────────────────────────────
T+0     1. 테스트 세션 생성 (session_id 기록)
        2. MV, RMV 모두 활성화 상태 확인
        3. 데이터 INSERT 시작 (30분간)
        4. 메트릭 수집 시작 (1분 주기)

T+30m   5. INSERT 중지
        6. 최종 메트릭 수집
        7. 테스트 세션 종료 마킹

T+35m   8. 결과 분석 쿼리 실행
```

### Round 2: 재현성 검증 (동일 절차 반복)

---

## 7. 결과 분석 쿼리

### 7.1 전체 리소스 사용량 비교
```sql
SELECT
    metric_source,
    sum(query_count) AS total_queries,
    sum(query_duration_ms) / 1000 AS total_duration_sec,
    formatReadableSize(sum(memory_usage_bytes)) AS total_memory,
    formatReadableSize(max(peak_memory_usage_bytes)) AS peak_memory,
    sum(read_rows) AS total_read_rows,
    formatReadableSize(sum(read_bytes)) AS total_read_bytes,
    sum(written_rows) AS total_written_rows,
    formatReadableSize(sum(written_bytes)) AS total_written_bytes
FROM mv_vs_rmv.resource_metrics
WHERE session_id = '<SESSION_ID>'
GROUP BY metric_source
ORDER BY metric_source;
```

### 7.2 시간대별 리소스 추이
```sql
SELECT
    toStartOfMinute(collected_at) AS minute,
    metric_source,
    sum(query_count) AS queries,
    sum(query_duration_ms) AS duration_ms,
    formatReadableSize(max(peak_memory_usage_bytes)) AS peak_memory
FROM mv_vs_rmv.resource_metrics
WHERE session_id = '<SESSION_ID>'
GROUP BY minute, metric_source
ORDER BY minute, metric_source;
```

### 7.3 Part 증가 추이 비교
```sql
SELECT
    toStartOfMinute(collected_at) AS minute,
    table_name,
    max(part_count) AS parts,
    max(active_parts) AS active,
    formatReadableSize(max(bytes_on_disk)) AS disk_size
FROM mv_vs_rmv.parts_history
WHERE session_id = '<SESSION_ID>'
GROUP BY minute, table_name
ORDER BY minute, table_name;
```

### 7.4 Merge 활동 비교
```sql
SELECT
    table_name,
    count() AS merge_count,
    sum(merge_duration_ms) / 1000 AS total_merge_sec,
    avg(merge_duration_ms) AS avg_merge_ms,
    sum(rows_read) AS total_rows_merged,
    formatReadableSize(sum(bytes_read)) AS total_bytes_merged,
    formatReadableSize(max(memory_usage)) AS peak_merge_memory
FROM mv_vs_rmv.merge_activity
WHERE session_id = '<SESSION_ID>'
GROUP BY table_name
ORDER BY table_name;
```

### 7.5 효율성 지표 계산
```sql
WITH 
mv_stats AS (
    SELECT 
        sum(written_rows) AS rows,
        sum(written_bytes) AS bytes,
        sum(query_duration_ms) AS duration
    FROM mv_vs_rmv.resource_metrics 
    WHERE session_id = '<SESSION_ID>' AND metric_source = 'MV'
),
rmv_stats AS (
    SELECT 
        sum(written_rows) AS rows,
        sum(written_bytes) AS bytes,
        sum(query_duration_ms) AS duration
    FROM mv_vs_rmv.resource_metrics 
    WHERE session_id = '<SESSION_ID>' AND metric_source = 'RMV'
)
SELECT
    'Resource Efficiency' AS metric,
    mv_stats.duration AS mv_duration_ms,
    rmv_stats.duration AS rmv_duration_ms,
    round(mv_stats.duration / rmv_stats.duration, 2) AS mv_to_rmv_ratio,
    formatReadableSize(mv_stats.bytes) AS mv_bytes,
    formatReadableSize(rmv_stats.bytes) AS rmv_bytes
FROM mv_stats, rmv_stats;
```

---

## 8. 주의사항 및 고려사항

### 8.1 RMV APPEND 모드 데이터 중복 방지
```sql
-- RMV는 APPEND 모드이므로 중복 삽입 가능성 있음
-- 해결책 1: WHERE 절에서 시간 범위를 명확히 지정
-- 해결책 2: ReplacingMergeTree 사용

-- 데이터 검증 쿼리
SELECT 
    'MV' AS source,
    count() AS rows,
    uniq(event_time_5min, event_type, country, device_type) AS unique_keys
FROM mv_vs_rmv.events_agg_mv
UNION ALL
SELECT 
    'RMV' AS source,
    count() AS rows,
    uniq(event_time_5min, event_type, country, device_type) AS unique_keys
FROM mv_vs_rmv.events_agg_rmv;
```

### 8.2 테스트 환경 초기화
```sql
-- 테스트 재실행 전 데이터 정리
TRUNCATE TABLE mv_vs_rmv.events_source;
TRUNCATE TABLE mv_vs_rmv.events_agg_mv;
TRUNCATE TABLE mv_vs_rmv.events_agg_rmv;
TRUNCATE TABLE mv_vs_rmv.resource_metrics;
TRUNCATE TABLE mv_vs_rmv.parts_history;
TRUNCATE TABLE mv_vs_rmv.merge_activity;

-- MV/RMV 상태 확인
SELECT 
    database, 
    name, 
    engine,
    is_refreshable,
    refresh_schedule
FROM system.tables
WHERE database = 'mv_vs_rmv'
  AND engine LIKE '%View%';
```

### 8.3 예상 리소스 차이 원인
| 요소 | MV | RMV |
|------|-----|------|
| 트리거 빈도 | 매 INSERT | 5분 1회 |
| 배치 크기 | 1000 rows | ~300,000 rows |
| Part 생성 | 1800회 | 6회 |
| Merge 부하 | 높음 | 낮음 |
| 지연 시간 | 즉시 | 최대 5분 |

---

## 9. 테스트 완료 후 정리

```sql
-- 테스트 세션 종료 마킹
ALTER TABLE mv_vs_rmv.test_sessions
UPDATE end_time = now64(3)
WHERE session_id = '<SESSION_ID>';

-- 전체 테스트 결과 요약 저장 (선택사항)
-- Canvas 또는 별도 문서로 결과 정리
```

---

## 10. 예상 결론

**MV가 유리한 경우**:
- 실시간 데이터 반영이 필수인 경우
- INSERT 빈도가 낮은 경우

**RMV가 유리한 경우**:
- 배치 지연(5분)이 허용되는 경우
- 고빈도 INSERT 환경
- 리소스 효율성이 중요한 경우
- 복잡한 aggregation 로직

이 테스트를 통해 실제 수치로 효율성 차이를 검증할 수 있습니다.
