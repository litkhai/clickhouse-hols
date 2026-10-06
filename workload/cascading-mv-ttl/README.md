# Data Lifecycle Management with Cascading Materialized Views and TTL

[English](#english) | [한국어](#한국어)

---

## English

> **Migrated, not verified.** Moved on 2026-10-06 from the author's notes site (clickhouse.kr), as written there. The steps and numbers have not been re-run in this repository. The English text is an LLM-assisted translation of the Korean original.

### Introduction

Running a large application means hundreds of millions of log records piling up in real time. Managing that data efficiently and querying it quickly is one of the biggest challenges data engineers face. ClickHouse offers powerful features for this problem: Materialized Views and TTL (Time To Live).

This article first looks at what a ClickHouse Materialized View is and how it differs from other databases. It then walks through building an automated data lifecycle management system by combining the Cascading Materialized View pattern with TTL, with hands-on steps.

### Understanding ClickHouse Materialized Views

#### Materialized Views in traditional databases

Start with how a Materialized View works in a traditional RDBMS such as PostgreSQL or MySQL. There, a Materialized View is a table that physically stores the result of a complex query.

```sql
-- PostgreSQL example
CREATE MATERIALIZED VIEW sales_summary AS
SELECT product_id, SUM(amount) as total_sales
FROM sales
GROUP BY product_id;
-- a full recomputation is needed when data is refreshed
REFRESH MATERIALIZED VIEW sales_summary;
```

The main characteristics and limits of the traditional approach are:

**Batch refresh**: The Materialized View is not updated automatically when data changes. You must run an explicit `REFRESH` command, and that recomputes all the data, which is expensive.

**Full recomputation overhead**: Even if a single row is added to the source table, refreshing the Materialized View means re-aggregating everything. The more data there is, the more this cost grows.

**Lack of real-time behaviour**: Because refreshes are batch-based, the latest data is not reflected immediately. This is a poor fit for real-time dashboards and analytics.

#### ClickHouse's different approach: Incremental Materialization

ClickHouse Materialized Views are designed around a completely different philosophy. The biggest difference is **incremental processing**.

**Real-time trigger**: In ClickHouse, a Materialized View is triggered automatically when data is INSERTed into the source table. No separate REFRESH command is needed.

**Incremental computation**: Instead of recomputing all the data, aggregation runs only on the newly arrived data. This is implemented through the state-based computation of `AggregateFunction`.

**Streaming processing**: Aggregation happens at the same time as the INSERT, so near-real-time analysis is possible.

Technically, a ClickHouse Materialized View consists of two components.

First, the **target table**: the table where the aggregated data is actually stored. It usually uses the `AggregatingMergeTree` engine.

Second, the **View that acts as the trigger**: it intercepts INSERTs into the source table, transforms them, and passes them to the target table.

#### Characteristics of ClickHouse Cloud

**SharedMergeTree engine**: ClickHouse Cloud uses engines of the `SharedMergeTree` family. They separate storage from compute and provide an architecture optimised for cloud environments.

**Automatic scaling**: Materialized View processing also scales automatically. When the incoming data volume grows, ClickHouse Cloud allocates resources automatically.

**Storage efficiency**: In the Cloud, storage cost is an important consideration. Reducing data volume through aggregation contributes directly to saving cost.

### Cascading Materialized Views: a staged aggregation strategy

#### What is the Cascading pattern?

A Cascading Materialized View chains several levels of Materialized Views to aggregate data progressively. Like a waterfall, data flows from one stage to the next and becomes more compressed and refined along the way.

The core idea of this pattern is to **lower the data granularity step by step**.

- **First stage**: aggregate per-second raw data to hourly
- **Second stage**: re-aggregate the hourly aggregates to daily
- **Third stage**: re-aggregate the daily aggregates to monthly

#### Why is Cascading needed?

Wouldn't a single Materialized View be enough? The reasons for the Cascading pattern are:

**Query performance**: When a user asks for "daily statistics for the last 6 months", using data that is already aggregated by day is much faster than aggregating the raw data every time.

**Storage efficiency**: The older the data, the less fine-grained it needs to be. There is no need to keep year-old data at minute resolution. Combining Cascading with TTL deletes the fine-grained data automatically and keeps only the aggregated data.

**Flexible retention policy**: Each aggregation level can have a different retention period. For example: hourly data for 7 days, daily data for 30 days, monthly data forever.

**Spreading the aggregation load**: Instead of doing all aggregation at once, the work is split into stages, which spreads the system load.

### Hands-on: implementing Cascading Materialized Views for application log data

Now implement Cascading Materialized Views and TTL with a concrete example: a system that processes log data from web and mobile applications.

#### Scenario design

The data we manage has these characteristics.

**Data type**: event logs from web apps, mobile apps and API services

**Data volume**: thousands of events per second

**Analysis requirements**: hourly and daily event statistics, error rate, response-time analysis

**Retention policy**:

- Raw data: process immediately, then discard (Null engine)
- Hourly aggregates: keep 7 days
- Daily aggregates: keep 30 days

##### Step 1: raw data intake table (Null engine)

First, create the table that receives the raw logs.

Here we use the `Null` engine.

*(Using the `Null` engine is only an example. The engine can differ depending on the use case.)*

```sql
CREATE TABLE blog_demo.app_logs_raw
(
    event_time DateTime,           -- event time
    app_name String,                -- application name
    event_type String,              -- event type
    user_id UInt64,                 -- user ID
    status_code UInt16,             -- HTTP status code
    response_time_ms UInt32,        -- response time (milliseconds)
    error_message String            -- error message
)
ENGINE = Null;
```

**What the Null engine means**: Data INSERTed into this table is not actually stored on disk. The table only acts as the trigger for the Materialized View. Because raw data is not kept, storage is saved.

This pattern is very useful when the raw form of data such as logs does not need to be kept for long and only the aggregated form is needed.

##### Step 2: hourly aggregate table

Create the table that stores data aggregated per hour.

```sql
CREATE TABLE blog_demo.app_logs_hourly
(
    event_hour DateTime,
    app_name String,
    event_type String,
    event_count AggregateFunction(sum, UInt64),
    unique_users AggregateFunction(uniq, UInt64),
    avg_response_time AggregateFunction(avg, UInt32),
    error_count AggregateFunction(sum, UInt64)
)
ENGINE = SharedAggregatingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
PARTITION BY toYYYYMM(event_hour)
ORDER BY (event_hour, app_name, event_type)
TTL event_hour + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;
```

**Key design points**:

**AggregateFunction types**: Columns such as `event_count` and `unique_users` use the `AggregateFunction` type rather than ordinary numeric types. This stores the intermediate state of the aggregate function so that further aggregation is possible later.

**SharedAggregatingMergeTree**: An engine optimised for ClickHouse Cloud. In the background it merges rows with the same key automatically and combines the AggregateFunction states.

**Partitioning**: `toYYYYMM(event_hour)` creates monthly partitions. This makes TTL and data management efficient.

**ORDER BY**: Sorted in the order `(event_hour, app_name, event_type)`. This order should be tuned to the query pattern.

**TTL setting**: `TTL event_hour + INTERVAL 7 DAY` means each row is deleted automatically 7 days after its event_hour.

##### Step 3: first Materialized View (Raw → Hourly)

Create the Materialized View that aggregates raw data per hour.

```sql
CREATE MATERIALIZED VIEW blog_demo.app_logs_hourly_mv
TO blog_demo.app_logs_hourly
AS
SELECT
    toStartOfHour(event_time) as event_hour,
    app_name,
    event_type,
    sumState(toUInt64(1)) as event_count,
    uniqState(user_id) as unique_users,
    avgState(response_time_ms) as avg_response_time,
    sumState(toUInt64(if(status_code >= 400, 1, 0))) as error_count
FROM blog_demo.app_logs_raw
GROUP BY event_hour, app_name, event_type;
```

**How it works**:

When data is INSERTed into the `app_logs_raw` table, this Materialized View is triggered automatically.

`toStartOfHour(event_time)` rounds the event time down to the hour and uses it as the grouping key.

**State functions**: `sumState`, `uniqState` and `avgState` produce the intermediate state of an aggregate function. These states can later be combined with `Merge` functions.

For example, `sumState(toUInt64(1))` counts each event as 1 to compute the total number of events.

`uniqState(user_id)` produces a HyperLogLog state to track the number of unique users.

`avgState(response_time_ms)` stores the sum and count needed to compute the average response time.

**Error counting**: `sumState(toUInt64(if(status_code >= 400, 1, 0)))` counts only the cases where the HTTP status code is 400 or higher.

##### Step 4: daily aggregate table

Create the table that stores data aggregated per day.

```sql
CREATE TABLE blog_demo.app_logs_daily
(
    event_date Date,
    app_name String,
    event_type String,
    event_count AggregateFunction(sum, UInt64),
    unique_users AggregateFunction(uniq, UInt64),
    avg_response_time AggregateFunction(avg, UInt32),
    error_count AggregateFunction(sum, UInt64)
)
ENGINE = SharedAggregatingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, app_name, event_type)
TTL event_date + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;
```

The structure is similar to the hourly aggregate table, with these differences:

Uses `event_date` (Date type) instead of `event_hour`

**TTL is set longer, at 30 days**: the strategy is to keep daily aggregates longer

##### Step 5: second Materialized View (Hourly → Daily)

Create the second Materialized View, which is the heart of Cascading.

```sql
CREATE MATERIALIZED VIEW blog_demo.app_logs_daily_mv
TO blog_demo.app_logs_daily
AS
SELECT
    toDate(event_hour) as event_date,
    app_name,
    event_type,
    sumMergeState(event_count) as event_count,
    uniqMergeState(unique_users) as unique_users,
    avgMergeState(avg_response_time) as avg_response_time,
    sumMergeState(error_count) as error_count
FROM blog_demo.app_logs_hourly
GROUP BY event_date, app_name, event_type;
```

**The key to Cascading - the MergeState functions**:

Note the `sumMergeState`, `uniqMergeState` and `avgMergeState` functions.

These functions read the AggregateFunction states stored in the `app_logs_hourly` table and combine them.

For example, 24 hourly `unique_users` states are merged into one daily state. This is not simply adding numbers; it is merging HyperLogLog data structures.

**Automatic trigger**: When new data is inserted into the `app_logs_hourly` table or a background merge happens, this Materialized View is also triggered automatically and updates the daily aggregate.

##### Checking the results

On ClickHouse Cloud, we entered 5,000 sample rows and checked the results.

**Query the hourly aggregate**:

```sql
SELECT 
    event_hour,
    app_name,
    sumMerge(event_count) as total_events,
    uniqMerge(unique_users) as unique_users
FROM blog_demo.app_logs_hourly
GROUP BY event_hour, app_name
ORDER BY event_hour DESC
LIMIT 10;
```

Result:

```text
┌────────event_hour────┬─app_name────┬─total_events─┬─unique_users─┐
│ 2025-11-08 13:00:00  │ web-app     │           11 │           11 │
│ 2025-11-08 13:00:00  │ api-service │           14 │           14 │
│ 2025-11-08 13:00:00  │ mobile-app  │            6 │            6 │
│ 2025-11-08 12:00:00  │ web-app     │           39 │           39 │
│ 2025-11-08 12:00:00  │ mobile-app  │           29 │           29 │
│ 2025-11-08 12:00:00  │ api-service │           32 │           32 │
└──────────────────────┴─────────────┴──────────────┴──────────────┘
```

**Query the daily aggregate**:

```sql
SELECT 
    event_date,
    app_name,
    sumMerge(event_count) as total_events,
    uniqMerge(unique_users) as unique_users,
    round(avgMerge(avg_response_time), 2) as avg_response_time_ms,
    sumMerge(error_count) as errors
FROM blog_demo.app_logs_daily
GROUP BY event_date, app_name
ORDER BY event_date DESC, app_name;
```

Result:

```text
┌─event_date─┬─app_name────┬─total_events─┬─unique_users─┬─avg_response_time_ms─┬─errors─┐
│ 2025-11-08 │ api-service │          448 │          438 │               297.74 │     45 │
│ 2025-11-08 │ mobile-app  │          478 │          475 │               300.42 │     59 │
│ 2025-11-08 │ web-app     │          462 │          456 │               303.72 │     50 │
│ 2025-11-07 │ api-service │          832 │          804 │               296.51 │     74 │
│ 2025-11-07 │ mobile-app  │          806 │          778 │               299.18 │     84 │
│ 2025-11-07 │ web-app     │          855 │          820 │               303.97 │     77 │
└────────────┴─────────────┴──────────────┴──────────────┴──────────────────────┴────────┘
```

**Check storage efficiency**:

```sql
SELECT 
    'hourly' as aggregation_level,
    count(*) as partition_count,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size
FROM system.parts
WHERE database = 'blog_demo' AND table = 'app_logs_hourly' AND active

UNION ALL

SELECT 
    'daily' as aggregation_level,
    count(*) as partition_count,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size
FROM system.parts
WHERE database = 'blog_demo' AND table = 'app_logs_daily' AND active;
```

Result:

```text
┌─aggregation_level─┬─partition_count─┬─compressed_size─┬─uncompressed_size─┐
│ hourly            │               1 │ 23.75 KiB       │ 48.50 KiB         │
│ daily             │               1 │ 19.82 KiB       │ 20.75 KiB         │
└───────────────────┴─────────────────┴─────────────────┴───────────────────┘
```

You can see that the daily aggregate takes much less space than the hourly aggregate.

#### Automatic data lifecycle management with TTL

##### How TTL works

TTL in ClickHouse is a powerful feature for defining the lifetime of data. After the set time has passed, data is deleted automatically or moved to other storage.

**Row-level TTL**: TTL applies to each row individually.

```sql
TTL event_hour + INTERVAL 7 DAY
```

This setting means "delete the row at the time the event_hour value plus 7 days is reached".

**Background processing**: TTL is processed during background merges. Data is not deleted immediately; expired data is removed when a merge happens.

**Partition-level optimisation**: Used together with partitioning, a whole partition can be dropped when all of it has expired, which improves performance considerably.

#### The synergy of Cascading + TTL

In our example the TTL strategy is:

**Raw data**: not stored, thanks to the Null engine (0 days)

**Hourly aggregate**: kept 7 days

**Daily aggregate**: kept 30 days

The effects of this strategy are:

**Automatic data archiving**: Older data survives only in an increasingly compressed form. Data older than 8 days loses its hourly resolution and keeps only daily resolution.

**Storage cost optimisation**: Fine-grained data is kept briefly and aggregated data is kept long, which cuts storage cost substantially.

**Better query performance**: Queries over older periods automatically use the compressed daily data, so they run faster.

**Operational automation**: ClickHouse manages the data lifecycle automatically, without separate batch jobs or cleanup scripts.

##### A more realistic production scenario

Consider a more complex, realistic scenario.

```sql
-- minute-level aggregate (kept 1 day)
TTL event_minute + INTERVAL 1 DAY
-- hourly aggregate (kept 7 days)
TTL event_hour + INTERVAL 7 DAY
-- daily aggregate (kept 90 days)
TTL event_date + INTERVAL 90 DAY
-- monthly aggregate (kept forever, no TTL)- no TTL setting
```

With four-level Cascading like this:

**Last 24 hours**: minute resolution, allowing near-real-time analysis

**Last 7 days**: hourly resolution for detailed trend analysis

**Last 90 days**: daily resolution for medium-term trends

**After 90 days**: monthly resolution for long-term trend analysis

### Best practices and caveats

##### 1. ORDER BY key design

ORDER BY directly affects query performance. Put the most frequently filtered columns first.

**Good example**:

```sql
ORDER BY (event_date, app_name, event_type)
-- if most queries read a specific date range
```

**Bad example**:

```sql
ORDER BY (app_name, event_type, event_date)
-- date-range queries run inefficiently
```

##### 2. Partitioning strategy

The partition key should be closely tied to TTL and data management.

**Monthly partitioning**: the right choice in most cases.

```sql
PARTITION BY toYYYYMM(event_date)
```

**Daily partitioning**: worth considering when the data volume is very large and the TTL is short.

```sql
PARTITION BY toYYYYMMDD(event_date)
```

**Caution**: Too many partitions actually hurt performance. In general, keep the number of partitions to a few hundred or fewer.

##### 3. Choosing AggregateFunction

Choosing the right AggregateFunction matters.

**Exact counts**: `count`, `sum`

**Approximate counts**: `uniq` (HyperLogLog-based, error rate ~2%)

**Exact distinct counts**: `uniqExact` (high memory usage)

**Quantiles**: `quantile`, `quantileTDigest`

##### 4. Order of creating Materialized Views

When implementing Cascading, create the Materialized Views **from the lowest level to the highest**.

1. Create the target tables (hourly, daily)
2. Create the first Materialized View (raw → hourly)
3. Create the second Materialized View (hourly → daily)

If you create them in the reverse order, data may not propagate correctly.

##### 5. Backfill strategy

To apply a Materialized View to existing data, you need an explicit INSERT SELECT.

```sql
-- backfill the existing hourly data into daily
INSERT INTO blog_demo.app_logs_daily
SELECT toDate(event_hour) as event_date, app_name, event_type, sumMergeState(event_count) as event_count, uniqMergeState(unique_users) as unique_users, avgMergeState(avg_response_time) as avg_response_time, sumMergeState(error_count) as error_count
FROM blog_demo.app_logs_hourly
GROUP BY event_date, app_name, event_type;
```

##### 6. Monitoring points

In production, monitor the following metrics.

**Materialized View lag**: the time it takes for data to propagate to each level

**Storage usage**: the size trend of each table

**Whether TTL is working**: whether expired data is actually being deleted

**Query performance**: response time of queries at each aggregation level

```sql
-- check the size per table
SELECT table, formatReadableSize(sum(bytes_on_disk)) as size
FROM system.parts
WHERE database = 'blog_demo' AND active
GROUP BY table
ORDER BY sum(bytes_on_disk) DESC;
```

### Conclusion

The Cascading pattern that combines ClickHouse Materialized Views and TTL is a powerful solution for managing large time-series data. The main advantages of this approach are:

- **Real-time aggregation**: unlike traditional batch approaches, data is processed as soon as it arrives.
- **Automated data lifecycle**: TTL manages old data automatically and reduces the operational burden.
- **Storage optimisation**: progressive aggregation compresses data and cuts storage cost substantially.
- **Query performance**: pre-aggregated data lets even complex analytical queries run fast.
- **Scalability**: combined with ClickHouse Cloud's automatic scaling, it adapts flexibly to growing data volume.

This pattern applies to many time-series scenarios such as log analytics, IoT sensor data, financial transaction data and web analytics. If you use ClickHouse, try building a more efficient and automated data platform with Cascading Materialized Views and TTL.

### References

- [ClickHouse Documentation: Cascading Materialized Views](https://clickhouse.com/docs/guides/developer/cascading-materialized-views)
- [ClickHouse YouTube: Advanced Materialized Views](https://www.youtube.com/watch?v=QDAJTKZT8y4)
- [ClickHouse Documentation: Manage data with TTL (time-to-live)](https://clickhouse.com/docs/guides/developer/ttl)

---

## 한국어

> **이관본, 미검증.** 2026-10-06 작성자의 노트 사이트(clickhouse.kr)에서 원문 그대로 옮겼습니다. 이 저장소에서 단계와 수치를 다시 실행하지 않았습니다. 영어본은 한국어 원문을 LLM 도움으로 번역한 것입니다.

### 들어가며

대규모 애플리케이션을 운영하다 보면 수억 건의 로그 데이터가 실시간으로 쌓이게 됩니다. 이러한 데이터를 효율적으로 관리하고 빠르게 조회하는 것은 데이터 엔지니어들이 직면하는 가장 큰 도전 과제 중 하나입니다. ClickHouse는 이러한 문제를 해결하기 위한 강력한 기능을 제공하는데, 바로 Materialized View와 TTL(Time To Live)입니다.

이 글에서는 ClickHouse의 Materialized View가 무엇인지, 다른 데이터베이스와 어떻게 다른지 살펴본 후, Cascading Materialized View 패턴과 TTL을 조합하여 자동화된 데이터 생명주기 관리 시스템을 구축하는 방법을 실습과 함께 상세히 다루겠습니다.

### ClickHouse Materialized View의 이해

#### 전통적인 데이터베이스의 Materialized View

먼저 PostgreSQL이나 MySQL 같은 전통적인 RDBMS에서 Materialized View가 어떻게 동작하는지 살펴보겠습니다. 이들 데이터베이스에서 Materialized View는 복잡한 쿼리 결과를 물리적으로 저장해두는 테이블입니다.

```sql
-- PostgreSQL 예시
CREATE MATERIALIZED VIEW sales_summary AS
SELECT product_id, SUM(amount) as total_sales
FROM sales
GROUP BY product_id;
-- 데이터 갱신 시 전체 재계산 필요
REFRESH MATERIALIZED VIEW sales_summary;
```

전통적인 방식의 주요 특징과 한계는 다음과 같습니다.

**배치 갱신 방식**: 데이터가 변경되어도 Materialized View는 자동으로 업데이트되지 않습니다. 명시적으로 `REFRESH` 명령을 실행해야 하며, 이는 전체 데이터를 다시 계산하는 비용이 큽니다.

**전체 재계산 오버헤드**: 원본 테이블에 단 한 건의 데이터가 추가되어도 Materialized View를 갱신하려면 전체 데이터를 다시 집계해야 합니다. 데이터가 많을수록 이 비용은 기하급수적으로 증가합니다.

**실시간성 부족**: 배치 방식의 갱신으로 인해 최신 데이터가 즉시 반영되지 않습니다. 실시간 대시보드나 분석에는 적합하지 않습니다.

#### ClickHouse의 혁신적인 접근: Incremental Materialization

ClickHouse의 Materialized View는 완전히 다른 철학으로 설계되었습니다. 가장 큰 차이점은 **증분 처리(Incremental Processing)** 방식입니다.

**실시간 트리거 방식**: ClickHouse에서 Materialized View는 원본 테이블에 데이터가 INSERT될 때 자동으로 트리거됩니다. 별도의 REFRESH 명령이 필요하지 않습니다.

**증분 계산**: 전체 데이터를 재계산하는 대신, 새로 들어온 데이터에 대해서만 집계를 수행합니다. 이는 `AggregateFunction`의 상태 기반 계산을 통해 구현됩니다.

**스트리밍 처리**: INSERT와 동시에 집계가 일어나므로, 실시간에 가까운 데이터 분석이 가능합니다.

ClickHouse의 Materialized View는 기술적으로 두 가지 구성 요소로 이루어집니다.

첫째, **대상 테이블(Target Table)**: 집계된 데이터가 실제로 저장되는 테이블입니다. 일반적으로 `AggregatingMergeTree` 엔진을 사용합니다.

둘째, **트리거 역할의 View**: 원본 테이블에 대한 INSERT를 가로채서 변환 후 대상 테이블로 전달하는 역할을 합니다.

#### ClickHouse Cloud의 특징

**SharedMergeTree 엔진**: ClickHouse Cloud에서는 `SharedMergeTree` 계열의 엔진을 사용합니다. 이는 스토리지와 컴퓨트를 분리하여 클라우드 환경에 최적화된 아키텍처를 제공합니다.

**자동 스케일링**: Materialized View의 처리도 자동으로 스케일됩니다. 데이터 유입량이 증가하면 ClickHouse Cloud가 자동으로 리소스를 할당합니다.

**스토리지 효율성**: Cloud 환경에서는 스토리지 비용이 중요한 고려사항입니다. 집계를 통해 데이터 볼륨을 줄이는 것이 비용 절감에 직접적으로 기여합니다.

### Cascading Materialized Views: 단계적 집계 전략

#### Cascading 패턴이란?

Cascading Materialized View는 여러 단계의 Materialized View를 연결하여 점진적으로 데이터를 집계하는 패턴입니다. 마치 폭포수처럼 데이터가 한 단계에서 다음 단계로 흘러가며 점점 더 압축되고 정제됩니다.

이 패턴의 핵심 아이디어는 **데이터의 해상도(granularity)를 단계적으로 낮추는 것**입니다.

- **첫 번째 단계**: 초 단위 원시 데이터를 시간 단위로 집계
- **두 번째 단계**: 시간 단위 집계를 일 단위로 재집계
- **세 번째 단계**: 일 단위 집계를 월 단위로 재집계

#### 왜 Cascading이 필요한가?

단일 Materialized View만 사용해도 충분하지 않을까요? Cascading 패턴이 필요한 이유는 다음과 같습니다.

**쿼리 성능 최적화**: 사용자가 "지난 6개월간의 일별 통계"를 조회할 때, 원시 데이터를 매번 집계하는 대신 이미 일 단위로 집계된 데이터를 사용하면 훨씬 빠릅니다.

**스토리지 효율성**: 오래된 데이터일수록 세밀한 해상도가 필요하지 않습니다. 1년 전 데이터를 분 단위로 보관할 필요는 없죠. Cascading과 TTL을 조합하면 자동으로 세밀한 데이터는 삭제하고 집계된 데이터만 유지할 수 있습니다.

**유연한 데이터 보관 정책**: 각 집계 레벨마다 다른 보관 기간을 설정할 수 있습니다. 예를 들어 시간별 데이터는 7일, 일별 데이터는 30일, 월별 데이터는 영구 보관하는 식입니다.

**점진적 집계 부하 분산**: 한 번에 모든 집계를 수행하는 대신, 단계적으로 나누어 처리하므로 시스템 부하가 분산됩니다.

### 실습: Application Log 데이터의 Cascading Materialized View 구현

이제 실제 사례를 통해 Cascading Materialized View와 TTL을 구현해보겠습니다. 웹/모바일 애플리케이션의 로그 데이터를 처리하는 시스템을 만들어보겠습니다.

#### 시나리오 설계

우리가 관리할 데이터는 다음과 같은 특성을 가집니다.

**데이터 유형**: 웹 앱, 모바일 앱, API 서비스의 이벤트 로그

**데이터 볼륨**: 초당 수천 건의 이벤트 발생

**분석 요구사항**: 시간대별, 일별 이벤트 통계, 에러율, 응답시간 분석

**보관 정책**:

- 원시 데이터: 즉시 처리 후 삭제 (Null 엔진 사용)
- 시간별 집계: 7일 보관
- 일별 집계: 30일 보관

##### 1단계: 원시 데이터 수신 테이블 (Null Engine)

먼저 원시 로그를 받는 테이블을 생성합니다. 

여기서는 `Null` 엔진을 사용해보겠습니다.

*(`Null` 엔진을 사용하는 것은 어디까지나 예시일 뿐, 유즈케이스에 따라 엔진은 달라질 수 있습니다.)*

```sql
CREATE TABLE blog_demo.app_logs_raw
(
    event_time DateTime,           -- 이벤트 발생 시각
    app_name String,                -- 애플리케이션 이름
    event_type String,              -- 이벤트 타입
    user_id UInt64,                 -- 사용자 ID
    status_code UInt16,             -- HTTP 상태 코드
    response_time_ms UInt32,        -- 응답 시간 (밀리초)
    error_message String            -- 에러 메시지
)
ENGINE = Null;
```

**Null 엔진의 의미**: 이 테이블에 INSERT된 데이터는 실제로 디스크에 저장되지 않습니다. 대신 Materialized View의 트리거 역할만 수행합니다. 원시 데이터를 보관하지 않으므로 스토리지를 절약할 수 있습니다.

이 패턴은 로그 데이터처럼 원시 형태를 장기간 보관할 필요가 없고, 집계된 형태만 필요한 경우에 매우 유용합니다.

##### 2단계: 시간별 집계 테이블

시간 단위로 집계된 데이터를 저장할 테이블을 생성합니다.

```sql
CREATE TABLE blog_demo.app_logs_hourly
(
    event_hour DateTime,
    app_name String,
    event_type String,
    event_count AggregateFunction(sum, UInt64),
    unique_users AggregateFunction(uniq, UInt64),
    avg_response_time AggregateFunction(avg, UInt32),
    error_count AggregateFunction(sum, UInt64)
)
ENGINE = SharedAggregatingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
PARTITION BY toYYYYMM(event_hour)
ORDER BY (event_hour, app_name, event_type)
TTL event_hour + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;
```

**핵심 설계 포인트**:

**AggregateFunction 타입**: `event_count`, `unique_users` 등의 컬럼은 일반적인 숫자 타입이 아닌 `AggregateFunction` 타입입니다. 이는 집계 함수의 중간 상태를 저장하여, 나중에 추가 집계가 가능하도록 합니다.

**SharedAggregatingMergeTree**: ClickHouse Cloud에 최적화된 엔진입니다. 백그라운드에서 같은 키를 가진 행들을 자동으로 병합(merge)하며, AggregateFunction 상태들을 결합합니다.

**파티셔닝**: `toYYYYMM(event_hour)`로 월별 파티션을 생성합니다. 이는 TTL 적용과 데이터 관리를 효율적으로 만듭니다.

**ORDER BY**: `(event_hour, app_name, event_type)` 순서로 정렬합니다. 이 순서는 쿼리 패턴에 맞춰 최적화되어야 합니다.

**TTL 설정**: `TTL event_hour + INTERVAL 7 DAY`는 각 행이 event_hour 시각으로부터 7일 후 자동으로 삭제됨을 의미합니다.

##### 3단계: 첫 번째 Materialized View (Raw → Hourly)

원시 데이터를 시간별로 집계하는 Materialized View를 생성합니다.

```sql
CREATE MATERIALIZED VIEW blog_demo.app_logs_hourly_mv
TO blog_demo.app_logs_hourly
AS
SELECT
    toStartOfHour(event_time) as event_hour,
    app_name,
    event_type,
    sumState(toUInt64(1)) as event_count,
    uniqState(user_id) as unique_users,
    avgState(response_time_ms) as avg_response_time,
    sumState(toUInt64(if(status_code >= 400, 1, 0))) as error_count
FROM blog_demo.app_logs_raw
GROUP BY event_hour, app_name, event_type;
```

**동작 원리**:

`app_logs_raw` 테이블에 데이터가 INSERT되면, 이 Materialized View가 자동으로 트리거됩니다.

`toStartOfHour(event_time)`으로 이벤트 시각을 시간 단위로 내림하여 그룹핑 키로 사용합니다.

**State 함수들**: `sumState`, `uniqState`, `avgState`는 집계 함수의 중간 상태를 생성합니다. 이 상태들은 나중에 `Merge` 함수로 결합할 수 있습니다.

예를 들어, `sumState(toUInt64(1))`은 각 이벤트를 1로 카운트하여 총 이벤트 수를 계산합니다.

`uniqState(user_id)`는 고유 사용자 수를 추적하기 위한 HyperLogLog 상태를 생성합니다.

`avgState(response_time_ms)`는 평균 응답시간 계산을 위한 합계와 카운트를 저장합니다.

**에러 카운팅**: `sumState(toUInt64(if(status_code >= 400, 1, 0)))`는 HTTP 상태 코드가 400 이상인 경우만 카운트합니다.

##### 4단계: 일별 집계 테이블

일 단위로 집계된 데이터를 저장할 테이블을 생성합니다.

```sql
CREATE TABLE blog_demo.app_logs_daily
(
    event_date Date,
    app_name String,
    event_type String,
    event_count AggregateFunction(sum, UInt64),
    unique_users AggregateFunction(uniq, UInt64),
    avg_response_time AggregateFunction(avg, UInt32),
    error_count AggregateFunction(sum, UInt64)
)
ENGINE = SharedAggregatingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, app_name, event_type)
TTL event_date + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;
```

시간별 집계 테이블과 구조가 유사하지만, 다음과 같은 차이점이 있습니다.

`event_hour` 대신 `event_date` (Date 타입) 사용

**TTL이 30일로 더 길게 설정**: 일별 집계는 더 오래 보관하는 전략

##### 5단계: 두 번째 Materialized View (Hourly → Daily)

Cascading의 핵심인 두 번째 Materialized View를 생성합니다.

```sql
CREATE MATERIALIZED VIEW blog_demo.app_logs_daily_mv
TO blog_demo.app_logs_daily
AS
SELECT
    toDate(event_hour) as event_date,
    app_name,
    event_type,
    sumMergeState(event_count) as event_count,
    uniqMergeState(unique_users) as unique_users,
    avgMergeState(avg_response_time) as avg_response_time,
    sumMergeState(error_count) as error_count
FROM blog_demo.app_logs_hourly
GROUP BY event_date, app_name, event_type;
```

**Cascading의 핵심 - MergeState 함수**:

여기서 주목할 점은 `sumMergeState`, `uniqMergeState`, `avgMergeState` 함수들입니다.

이 함수들은 `app_logs_hourly` 테이블에 저장된 AggregateFunction 상태들을 읽어서 결합합니다.

예를 들어, 24개의 시간별 `unique_users` 상태를 하나의 일별 상태로 병합합니다. 이는 단순히 숫자를 더하는 것이 아니라, HyperLogLog 데이터 구조를 병합하는 것입니다.

**자동 트리거**: `app_logs_hourly` 테이블에 새로운 데이터가 삽입되거나 백그라운드 병합이 일어날 때, 이 Materialized View도 자동으로 트리거되어 일별 집계를 업데이트합니다.

##### 실습 결과 확인

실제로 ClickHouse Cloud에서 5,000건의 샘플 데이터를 입력하고 결과를 확인해보겠습니다.

**시간별 집계 조회**:

```sql
SELECT 
    event_hour,
    app_name,
    sumMerge(event_count) as total_events,
    uniqMerge(unique_users) as unique_users
FROM blog_demo.app_logs_hourly
GROUP BY event_hour, app_name
ORDER BY event_hour DESC
LIMIT 10;
```

결과:

```text
┌────────event_hour────┬─app_name────┬─total_events─┬─unique_users─┐
│ 2025-11-08 13:00:00  │ web-app     │           11 │           11 │
│ 2025-11-08 13:00:00  │ api-service │           14 │           14 │
│ 2025-11-08 13:00:00  │ mobile-app  │            6 │            6 │
│ 2025-11-08 12:00:00  │ web-app     │           39 │           39 │
│ 2025-11-08 12:00:00  │ mobile-app  │           29 │           29 │
│ 2025-11-08 12:00:00  │ api-service │           32 │           32 │
└──────────────────────┴─────────────┴──────────────┴──────────────┘
```

**일별 집계 조회**:

```sql
SELECT 
    event_date,
    app_name,
    sumMerge(event_count) as total_events,
    uniqMerge(unique_users) as unique_users,
    round(avgMerge(avg_response_time), 2) as avg_response_time_ms,
    sumMerge(error_count) as errors
FROM blog_demo.app_logs_daily
GROUP BY event_date, app_name
ORDER BY event_date DESC, app_name;
```

결과:

```text
┌─event_date─┬─app_name────┬─total_events─┬─unique_users─┬─avg_response_time_ms─┬─errors─┐
│ 2025-11-08 │ api-service │          448 │          438 │               297.74 │     45 │
│ 2025-11-08 │ mobile-app  │          478 │          475 │               300.42 │     59 │
│ 2025-11-08 │ web-app     │          462 │          456 │               303.72 │     50 │
│ 2025-11-07 │ api-service │          832 │          804 │               296.51 │     74 │
│ 2025-11-07 │ mobile-app  │          806 │          778 │               299.18 │     84 │
│ 2025-11-07 │ web-app     │          855 │          820 │               303.97 │     77 │
└────────────┴─────────────┴──────────────┴──────────────┴──────────────────────┴────────┘
```

**스토리지 효율성 확인**:

```sql
SELECT 
    'hourly' as aggregation_level,
    count(*) as partition_count,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size
FROM system.parts
WHERE database = 'blog_demo' AND table = 'app_logs_hourly' AND active

UNION ALL

SELECT 
    'daily' as aggregation_level,
    count(*) as partition_count,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size
FROM system.parts
WHERE database = 'blog_demo' AND table = 'app_logs_daily' AND active;
```

결과:

```text
┌─aggregation_level─┬─partition_count─┬─compressed_size─┬─uncompressed_size─┐
│ hourly            │               1 │ 23.75 KiB       │ 48.50 KiB         │
│ daily             │               1 │ 19.82 KiB       │ 20.75 KiB         │
└───────────────────┴─────────────────┴─────────────────┴───────────────────┘
```

일별 집계가 시간별 집계보다 훨씬 작은 용량을 차지하는 것을 확인할 수 있습니다.

#### TTL을 통한 자동 Data Lifecycle Management

##### TTL의 동작 원리

ClickHouse의 TTL은 데이터의 수명을 정의하는 강력한 기능입니다. 설정된 시간이 지나면 데이터가 자동으로 삭제되거나 다른 스토리지로 이동됩니다.

**행 레벨 TTL**: 각 행마다 개별적으로 TTL이 적용됩니다.

```sql
TTL event_hour + INTERVAL 7 DAY
```

이 설정은 "event_hour 값에 7일을 더한 시점에 해당 행을 삭제한다"는 의미입니다.

**백그라운드 처리**: TTL은 백그라운드 병합(merge) 과정에서 처리됩니다. 즉시 삭제되는 것이 아니라, 병합이 일어날 때 만료된 데이터가 제거됩니다.

**파티션 단위 최적화**: 파티셔닝과 함께 사용하면, 전체 파티션이 만료되었을 때 파티션 자체를 삭제하여 성능을 크게 향상시킬 수 있습니다.

#### Cascading + TTL 조합의 시너지

우리의 예제에서 TTL 전략은 다음과 같습니다.

**Raw 데이터**: Null 엔진으로 저장 안 함 (0일)

**Hourly 집계**: 7일 보관

**Daily 집계**: 30일 보관

이 전략의 효과는 다음과 같습니다.

**자동 데이터 아카이빙**: 오래된 데이터는 점점 더 압축된 형태로만 남습니다. 8일 전 데이터는 시간별 해상도는 사라지고 일별 해상도만 남습니다.

**스토리지 비용 최적화**: 세밀한 데이터는 짧게, 집계된 데이터는 길게 보관하여 스토리지 비용을 대폭 절감합니다.

**쿼리 성능 향상**: 오래된 기간을 조회할 때는 자동으로 압축된 일별 데이터를 사용하므로 쿼리가 빨라집니다.

**운영 자동화**: 별도의 배치 작업이나 데이터 정리 스크립트 없이 ClickHouse가 자동으로 데이터 생명주기를 관리합니다.

##### 실제 프로덕션 시나리오 예시

더 복잡한 실제 시나리오를 생각해보겠습니다.

```sql
-- 분 단위 집계 (1일 보관)
TTL event_minute + INTERVAL 1 DAY
-- 시간 단위 집계 (7일 보관)
TTL event_hour + INTERVAL 7 DAY
-- 일 단위 집계 (90일 보관)
TTL event_date + INTERVAL 90 DAY
-- 월 단위 집계 (영구 보관, TTL 없음)- TTL 설정 없음
```

이렇게 4단계 Cascading을 구성하면:

**최근 24시간**: 분 단위 해상도로 실시간에 가까운 분석 가능

**최근 7일**: 시간 단위 해상도로 상세한 트렌드 분석

**최근 90일**: 일 단위 해상도로 중기 트렌드 파악

**90일 이후**: 월 단위 해상도로 장기 트렌드 분석

### Best Practices 및 주의사항

##### 1. ORDER BY 키 설계

ORDER BY는 쿼리 성능에 직접적인 영향을 미칩니다. 가장 자주 필터링하는 컬럼을 앞쪽에 배치해야 합니다.

**좋은 예**:

```sql
ORDER BY (event_date, app_name, event_type)
-- 대부분의 쿼리가 특정 날짜 범위를 조회한다면
```

**나쁜 예**:

```sql
ORDER BY (app_name, event_type, event_date)
-- 날짜 범위 쿼리가 비효율적으로 동작
```

##### 2. 파티셔닝 전략

파티션 키는 TTL 및 데이터 관리와 밀접하게 연관되어야 합니다.

**월별 파티셔닝**: 대부분의 경우 적절한 선택입니다.

```sql
PARTITION BY toYYYYMM(event_date)
```

**일별 파티셔닝**: 데이터 볼륨이 매우 크고 짧은 TTL을 사용하는 경우 고려할 수 있습니다.

```sql
PARTITION BY toYYYYMMDD(event_date)
```

**주의**: 파티션이 너무 많으면 오히려 성능이 저하됩니다. 일반적으로 수백 개 이하의 파티션을 유지하는 것이 좋습니다.

##### 3. AggregateFunction 선택

적절한 AggregateFunction을 선택하는 것이 중요합니다.

**정확한 카운트**: `count`, `sum`

**근사 카운트**: `uniq` (HyperLogLog 기반, 오차율 ~2%)

**정확한 고유 값 카운트**: `uniqExact` (메모리 사용량 높음)

**분위수**: `quantile`, `quantileTDigest`

##### 4. Materialized View 생성 순서

Cascading을 구현할 때는 **하위 레벨부터 상위 레벨 순서로** Materialized View를 생성해야 합니다.

1. 대상 테이블들 생성 (hourly, daily)
2. 첫 번째 Materialized View 생성 (raw → hourly)
3. 두 번째 Materialized View 생성 (hourly → daily)

역순으로 생성하면 데이터가 올바르게 전파되지 않을 수 있습니다.

##### 5. 백필(Backfill) 전략

기존 데이터에 대해 Materialized View를 적용하려면 명시적인 INSERT SELECT가 필요합니다.

```sql
-- 기존 hourly 데이터를 daily로 백필
INSERT INTO blog_demo.app_logs_daily
SELECT toDate(event_hour) as event_date, app_name, event_type, sumMergeState(event_count) as event_count, uniqMergeState(unique_users) as unique_users, avgMergeState(avg_response_time) as avg_response_time, sumMergeState(error_count) as error_count
FROM blog_demo.app_logs_hourly
GROUP BY event_date, app_name, event_type;
```

##### 6. 모니터링 포인트

프로덕션 환경에서는 다음 메트릭들을 모니터링해야 합니다.

**Materialized View 지연**: 데이터가 각 레벨로 전파되는 시간

**스토리지 사용량**: 각 테이블의 용량 추이

**TTL 작동 여부**: 만료된 데이터가 실제로 삭제되고 있는지

**쿼리 성능**: 각 집계 레벨의 쿼리 응답 시간

```sql
-- 테이블별 용량 확인
SELECT table, formatReadableSize(sum(bytes_on_disk)) as size
FROM system.parts
WHERE database = 'blog_demo' AND active
GROUP BY table
ORDER BY sum(bytes_on_disk) DESC;
```

### 결론

ClickHouse의 Materialized View와 TTL을 조합한 Cascading 패턴은 대규모 시계열 데이터를 관리하는 강력한 솔루션입니다. 이 접근 방식의 핵심 장점은 다음과 같습니다.

- **실시간 집계**: 전통적인 배치 방식과 달리 데이터가 들어오는 즉시 처리됩니다.
- **자동화된 데이터 생명주기**: TTL을 통해 오래된 데이터를 자동으로 관리하여 운영 부담을 줄입니다.
- **스토리지 최적화**: 점진적 집계로 데이터를 압축하여 스토리지 비용을 대폭 절감합니다.
- **쿼리 성능**: 사전 집계된 데이터를 활용하여 복잡한 분석 쿼리도 빠르게 처리합니다.
- **확장성**: ClickHouse Cloud의 자동 스케일링과 결합하여 데이터 볼륨 증가에 유연하게 대응합니다.

이 패턴은 로그 분석, IoT 센서 데이터, 금융 거래 데이터, 웹 분석 등 다양한 시계열 데이터 처리 시나리오에 적용할 수 있습니다. ClickHouse를 사용한다면 Cascading Materialized View와 TTL을 활용하여 더 효율적이고 자동화된 데이터 플랫폼을 구축해보시기 바랍니다.

### 참고 자료

- [ClickHouse Documentation: Cascading Materialized Views](https://clickhouse.com/docs/guides/developer/cascading-materialized-views)
- [ClickHouse YouTube: Advanced Materialized Views](https://www.youtube.com/watch?v=QDAJTKZT8y4)
- [ClickHouse Documentation: Manage data with TTL (time-to-live)](https://clickhouse.com/docs/guides/developer/ttl)
