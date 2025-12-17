# ClickHouse Insert 시점 Deduplication 테스트 계획서

**문서 버전:** 1.0  
**작성일:** 2024년 12월  
**작성자:** ClickHouse Solutions Team  
**데이터베이스:** `dedup`

---

## 1. 개요

### 1.1 배경

고객은 Java 기반 애플리케이션에서 ClickHouse로 row-by-row insert를 수행하고 있으며, upstream 시스템이 at-least-once semantic을 따르기 때문에 데이터 중복이 발생할 수 있다. 또한 insert된 데이터는 cascading materialized view로 연결되어 downstream 집계에 활용된다.

### 1.2 목적

본 테스트는 다음 사항을 검증한다.

- 다양한 ClickHouse Table Engine의 deduplication 효과 비교 분석
- Row-by-row insert 환경에서의 성능 영향 측정
- Cascading Materialized View 환경에서 데이터 정합성 확인
- 운영 환경 적용을 위한 최적 구성 도출

### 1.3 테스트 범위

| 구분 | 포함 | 제외 |
|------|------|------|
| Table Engine | ReplacingMergeTree, CollapsingMergeTree, AggregatingMergeTree | 기타 특수 Engine |
| Insert 방식 | Row-by-row, Micro-batch, Batch | Kafka/Stream insert |
| MV 유형 | 일반 MV, Refreshable MV | Projection |
| 환경 | ClickHouse Cloud | Self-managed cluster |

### 1.4 Deduplication Key

모든 테스트에서 다음 컬럼 조합을 Primary/Dedup Key로 사용한다.

```
timestamp (DateTime64(3), ms 단위) + account (String) + product (String)
```

---

## 2. 테스트 환경

### 2.1 데이터베이스 설정

```sql
CREATE DATABASE IF NOT EXISTS dedup;
USE dedup;
```

### 2.2 ClickHouse Cloud 사양

```
Service Type: Production
Cloud Provider: AWS / GCP (고객 환경에 맞춤)
Region: ap-northeast-2 (서울) 또는 고객 지정
Tier: 권장 - 16 vCPU, 64GB RAM (테스트용 최소 8 vCPU)
```

### 2.3 테스트 데이터 특성

| 파라미터 | 값 | 설명 |
|----------|-----|------|
| 총 레코드 수 | 100,000 ~ 1,000,000 | 단계별 증가 |
| Unique 레코드 비율 | 70% | 30%는 의도적 중복 |
| Account cardinality | 1,000 | 고유 계정 수 |
| Product cardinality | 500 | 고유 제품 수 |
| 시간 범위 | 1시간 | 테스트 데이터 생성 범위 |

---

## 3. 테스트 시나리오 개요

```
Phase 1: 기본 Engine 비교
├── 1A: ReplacingMergeTree
├── 1B: CollapsingMergeTree
└── 1C: AggregatingMergeTree

Phase 2: Insert 패턴별 성능
├── 2A: Row-by-row (고객 현재 방식)
├── 2B: Micro-batch (100 rows)
└── 2C: Batch (1,000+ rows)

Phase 3: 권장 아키텍처 검증
├── 3A: Landing → Main (RMT) 구조
└── 3B: Async Insert 효과

Phase 4: Cascading MV 정합성
├── 4A: 일반 MV 체인
└── 4B: Refreshable MV 체인

Phase 5: 부하 테스트
└── 5A: 지속적 insert + 동시 쿼리
```

---

## 4. Phase 1: 기본 Engine 비교

### 4.1 목적

동일한 중복 데이터에 대해 각 Table Engine의 deduplication 동작 방식과 효과를 비교한다.

### 4.2 테이블 생성 DDL

```sql
-- 베이스라인 (일반 MergeTree)
CREATE TABLE dedup.p1_baseline (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    region LowCardinality(String),
    status LowCardinality(String),
    description String,
    extra_data String
) ENGINE = MergeTree()
ORDER BY (timestamp, account, product);

-- ReplacingMergeTree
CREATE TABLE dedup.p1_replacing (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    region LowCardinality(String),
    status LowCardinality(String),
    description String,
    extra_data String,
    _version UInt64 DEFAULT toUInt64(now64(3))
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (timestamp, account, product);

-- CollapsingMergeTree
CREATE TABLE dedup.p1_collapsing (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    region LowCardinality(String),
    status LowCardinality(String),
    description String,
    extra_data String,
    sign Int8 DEFAULT 1
) ENGINE = CollapsingMergeTree(sign)
ORDER BY (timestamp, account, product);

-- AggregatingMergeTree
CREATE TABLE dedup.p1_aggregating (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value SimpleAggregateFunction(any, Float64),
    metric_count SimpleAggregateFunction(any, UInt64),
    category SimpleAggregateFunction(any, String),
    region SimpleAggregateFunction(any, String),
    status SimpleAggregateFunction(any, String),
    description SimpleAggregateFunction(any, String),
    extra_data SimpleAggregateFunction(any, String)
) ENGINE = AggregatingMergeTree()
ORDER BY (timestamp, account, product);
```

### 4.3 테스트 스크립트

```python
#!/usr/bin/env python3
"""
Phase 1: Engine 비교 테스트
파일명: phase1_engine_comparison.py
"""

import clickhouse_connect
import random
import time
from datetime import datetime, timedelta
from dataclasses import dataclass
from typing import List, Tuple
import json

@dataclass
class TestConfig:
    host: str = "your-host.clickhouse.cloud"
    port: int = 8443
    username: str = "default"
    password: str = "your-password"
    database: str = "dedup"
    total_unique_records: int = 10000
    duplicate_rate: float = 0.3
    account_cardinality: int = 1000
    product_cardinality: int = 500

@dataclass
class TestRecord:
    timestamp: datetime
    account: str
    product: str
    metric_value: float
    metric_count: int
    category: str
    region: str
    status: str
    description: str
    extra_data: str

class DataGenerator:
    CATEGORIES = ['electronics', 'clothing', 'food', 'furniture', 'sports']
    REGIONS = ['asia', 'europe', 'americas', 'oceania', 'africa']
    STATUSES = ['active', 'pending', 'completed', 'cancelled']
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.base_time = datetime.now() - timedelta(hours=1)
        
    def generate(self) -> Tuple[List[TestRecord], int]:
        unique_records = []
        for i in range(self.config.total_unique_records):
            record = TestRecord(
                timestamp=self.base_time + timedelta(milliseconds=i * 360),
                account=f'account_{random.randint(1, self.config.account_cardinality):04d}',
                product=f'product_{random.randint(1, self.config.product_cardinality):03d}',
                metric_value=round(random.random() * 10000, 2),
                metric_count=random.randint(1, 1000),
                category=random.choice(self.CATEGORIES),
                region=random.choice(self.REGIONS),
                status=random.choice(self.STATUSES),
                description=f'Record {i}',
                extra_data=json.dumps({'idx': i})
            )
            unique_records.append(record)
        
        num_dup = int(len(unique_records) * self.config.duplicate_rate)
        duplicates = random.sample(unique_records, num_dup)
        all_records = unique_records + duplicates
        random.shuffle(all_records)
        return all_records, len(unique_records)

class Phase1Tester:
    def __init__(self, config: TestConfig):
        self.config = config
        self.client = clickhouse_connect.get_client(
            host=config.host, port=config.port,
            username=config.username, password=config.password,
            database=config.database, secure=True
        )
        
    def insert_batch(self, table: str, records: List[TestRecord]) -> float:
        columns = ['timestamp', 'account', 'product', 'metric_value', 
                   'metric_count', 'category', 'region', 'status', 
                   'description', 'extra_data']
        data = [[r.timestamp, r.account, r.product, r.metric_value,
                 r.metric_count, r.category, r.region, r.status,
                 r.description, r.extra_data] for r in records]
        start = time.time()
        self.client.insert(table, data, column_names=columns)
        return time.time() - start
    
    def verify_counts(self, table: str, engine_type: str) -> dict:
        result = {'table': table, 'engine': engine_type}
        result['raw_count'] = self.client.command(f"SELECT count() FROM {table}")
        
        if engine_type in ['replacing', 'collapsing', 'aggregating']:
            result['dedup_count'] = self.client.command(f"SELECT count() FROM {table} FINAL")
        else:
            result['dedup_count'] = self.client.command(
                f"SELECT count(DISTINCT (timestamp, account, product)) FROM {table}")
        
        self.client.command(f"OPTIMIZE TABLE {table} FINAL")
        time.sleep(2)
        result['after_optimize'] = self.client.command(f"SELECT count() FROM {table}")
        return result

def run_phase1():
    config = TestConfig()
    tester = Phase1Tester(config)
    generator = DataGenerator(config)
    
    print("=" * 60)
    print("Phase 1: Engine 비교 테스트")
    print("=" * 60)
    
    records, expected_unique = generator.generate()
    print(f"총 레코드: {len(records)}, 예상 Unique: {expected_unique}")
    
    tables = [
        ('dedup.p1_baseline', 'baseline'),
        ('dedup.p1_replacing', 'replacing'),
        ('dedup.p1_collapsing', 'collapsing'),
        ('dedup.p1_aggregating', 'aggregating'),
    ]
    
    results = []
    for table, engine in tables:
        print(f"\nTesting {table}...")
        elapsed = tester.insert_batch(table, records)
        counts = tester.verify_counts(table, engine)
        results.append({**counts, 'insert_time': elapsed})
        print(f"  Raw: {counts['raw_count']}, Dedup: {counts['dedup_count']}, "
              f"Optimized: {counts['after_optimize']}")
    
    return results

if __name__ == '__main__':
    run_phase1()
```

### 4.4 예상 결과

| Engine | Raw Count | Dedup Count | OPTIMIZE 후 | 평가 |
|--------|-----------|-------------|-------------|------|
| baseline | 13,000 | 10,000 (DISTINCT) | 13,000 | 중복 유지 |
| replacing | 13,000 | 10,000 (FINAL) | 10,000 | ✅ Dedup 성공 |
| collapsing | 13,000 | 13,000 | 13,000 | ❌ Sign 관리 필요 |
| aggregating | 13,000 | 10,000 (FINAL) | 10,000 | ✅ Dedup 성공 |

---

## 5. Phase 2: Insert 패턴별 성능

### 5.1 목적

Row-by-row vs Batch insert의 성능 차이를 측정한다.

### 5.2 테이블 생성 DDL

```sql
CREATE TABLE dedup.p2_row_by_row (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    region LowCardinality(String),
    status LowCardinality(String),
    description String,
    extra_data String,
    _version UInt64 DEFAULT toUInt64(now64(3))
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (timestamp, account, product);

CREATE TABLE dedup.p2_micro_batch AS dedup.p2_row_by_row;
CREATE TABLE dedup.p2_batch AS dedup.p2_row_by_row;
CREATE TABLE dedup.p2_async_insert AS dedup.p2_row_by_row;
```

### 5.3 테스트 스크립트

```python
#!/usr/bin/env python3
"""
Phase 2: Insert 패턴 성능 테스트
파일명: phase2_insert_patterns.py
"""

import clickhouse_connect
import time
from phase1_engine_comparison import TestConfig, DataGenerator, TestRecord
from typing import List

class Phase2Tester:
    def __init__(self, config: TestConfig):
        self.config = config
        self.client = clickhouse_connect.get_client(
            host=config.host, port=config.port,
            username=config.username, password=config.password,
            database=config.database, secure=True
        )
    
    def test_row_by_row(self, records: List[TestRecord], limit: int = 1000):
        table = 'dedup.p2_row_by_row'
        start = time.time()
        for r in records[:limit]:
            sql = f"""INSERT INTO {table} 
                (timestamp, account, product, metric_value, metric_count,
                 category, region, status, description, extra_data)
                VALUES ('{r.timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}',
                    '{r.account}', '{r.product}', {r.metric_value},
                    {r.metric_count}, '{r.category}', '{r.region}',
                    '{r.status}', '{r.description}', '{r.extra_data}')"""
            self.client.command(sql)
        elapsed = time.time() - start
        return {'method': 'row_by_row', 'records': limit, 
                'elapsed': elapsed, 'rate': limit / elapsed}
    
    def test_micro_batch(self, records: List[TestRecord], 
                         batch_size: int = 100, limit: int = 10000):
        table = 'dedup.p2_micro_batch'
        columns = ['timestamp', 'account', 'product', 'metric_value', 
                   'metric_count', 'category', 'region', 'status', 
                   'description', 'extra_data']
        start = time.time()
        for i in range(0, min(limit, len(records)), batch_size):
            batch = records[i:i + batch_size]
            data = [[r.timestamp, r.account, r.product, r.metric_value,
                     r.metric_count, r.category, r.region, r.status,
                     r.description, r.extra_data] for r in batch]
            self.client.insert(table, data, column_names=columns)
        elapsed = time.time() - start
        return {'method': 'micro_batch', 'records': limit, 
                'elapsed': elapsed, 'rate': limit / elapsed}
    
    def test_batch(self, records: List[TestRecord], limit: int = 10000):
        table = 'dedup.p2_batch'
        columns = ['timestamp', 'account', 'product', 'metric_value', 
                   'metric_count', 'category', 'region', 'status', 
                   'description', 'extra_data']
        data = [[r.timestamp, r.account, r.product, r.metric_value,
                 r.metric_count, r.category, r.region, r.status,
                 r.description, r.extra_data] for r in records[:limit]]
        start = time.time()
        self.client.insert(table, data, column_names=columns)
        elapsed = time.time() - start
        return {'method': 'batch', 'records': limit, 
                'elapsed': elapsed, 'rate': limit / elapsed}
    
    def test_async_insert(self, records: List[TestRecord], limit: int = 1000):
        table = 'dedup.p2_async_insert'
        self.client.command("SET async_insert = 1")
        self.client.command("SET wait_for_async_insert = 0")
        start = time.time()
        for r in records[:limit]:
            sql = f"""INSERT INTO {table} 
                (timestamp, account, product, metric_value, metric_count,
                 category, region, status, description, extra_data)
                VALUES ('{r.timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}',
                    '{r.account}', '{r.product}', {r.metric_value},
                    {r.metric_count}, '{r.category}', '{r.region}',
                    '{r.status}', '{r.description}', '{r.extra_data}')"""
            self.client.command(sql)
        elapsed = time.time() - start
        self.client.command("SET async_insert = 0")
        return {'method': 'async_insert', 'records': limit, 
                'elapsed': elapsed, 'rate': limit / elapsed}

def run_phase2():
    config = TestConfig()
    tester = Phase2Tester(config)
    generator = DataGenerator(config)
    records, _ = generator.generate()
    
    print("=" * 60)
    print("Phase 2: Insert 패턴 성능 테스트")
    print("=" * 60)
    
    results = [
        tester.test_row_by_row(records, limit=1000),
        tester.test_micro_batch(records, batch_size=100, limit=10000),
        tester.test_batch(records, limit=10000),
        tester.test_async_insert(records, limit=1000),
    ]
    
    print(f"{'Method':<20} {'Records':<10} {'Time(s)':<10} {'Rate(r/s)':<12}")
    for r in results:
        print(f"{r['method']:<20} {r['records']:<10} {r['elapsed']:<10.2f} {r['rate']:<12.1f}")
    
    return results

if __name__ == '__main__':
    run_phase2()
```

### 5.4 예상 결과

| Method | Records | Time (s) | Rate (rows/s) |
|--------|---------|----------|---------------|
| row_by_row | 1,000 | ~30-60 | ~15-30 |
| micro_batch | 10,000 | ~5-10 | ~1,000-2,000 |
| batch | 10,000 | ~1-2 | ~5,000-10,000 |
| async_insert | 1,000 | ~10-20 | ~50-100 |

---

## 6. Phase 3: 권장 아키텍처 검증

### 6.1 아키텍처 다이어그램

```
[Java App] ──▶ [p3_landing] ──MV──▶ [p3_main] ──Refreshable MV──▶ [p3_hourly_agg]
               (MergeTree)          (ReplacingMT)                        │
               TTL 1 hour                                                ▼
                                                                 [p3_daily_agg]
```

### 6.2 테이블 생성 DDL

```sql
-- Landing 테이블
CREATE TABLE dedup.p3_landing (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    region LowCardinality(String),
    status LowCardinality(String),
    description String,
    extra_data String,
    _insert_time DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
ORDER BY (timestamp, account, product)
TTL toDateTime(_insert_time) + INTERVAL 1 HOUR;

-- Main 테이블
CREATE TABLE dedup.p3_main (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    region LowCardinality(String),
    status LowCardinality(String),
    description String,
    extra_data String,
    _version UInt64
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (timestamp, account, product);

-- Landing → Main MV
CREATE MATERIALIZED VIEW dedup.p3_landing_to_main_mv TO dedup.p3_main AS
SELECT *, toUInt64(now64(3)) as _version FROM dedup.p3_landing;

-- Hourly Aggregation (Refreshable MV)
CREATE MATERIALIZED VIEW dedup.p3_hourly_agg
REFRESH EVERY 1 MINUTE
ENGINE = MergeTree()
ORDER BY (hour, account, category)
AS SELECT 
    toStartOfHour(timestamp) as hour,
    account,
    category,
    count() as event_count,
    uniq(timestamp, product) as unique_events,
    sum(metric_value) as total_metric_value
FROM dedup.p3_main FINAL
GROUP BY hour, account, category;

-- Daily Aggregation
CREATE MATERIALIZED VIEW dedup.p3_daily_agg
REFRESH EVERY 5 MINUTE DEPENDS ON dedup.p3_hourly_agg
ENGINE = MergeTree()
ORDER BY (day, account)
AS SELECT 
    toDate(hour) as day,
    account,
    sum(unique_events) as daily_unique_events,
    sum(total_metric_value) as daily_metric_value
FROM dedup.p3_hourly_agg
GROUP BY day, account;
```

### 6.3 테스트 스크립트

```python
#!/usr/bin/env python3
"""
Phase 3: 권장 아키텍처 검증
파일명: phase3_architecture.py
"""

import clickhouse_connect
import time
from phase1_engine_comparison import TestConfig, DataGenerator

class Phase3Tester:
    def __init__(self, config: TestConfig):
        self.config = config
        self.client = clickhouse_connect.get_client(
            host=config.host, port=config.port,
            username=config.username, password=config.password,
            database=config.database, secure=True
        )
    
    def insert_to_landing(self, records, batch_size=1000):
        table = 'dedup.p3_landing'
        columns = ['timestamp', 'account', 'product', 'metric_value', 
                   'metric_count', 'category', 'region', 'status', 
                   'description', 'extra_data']
        start = time.time()
        for i in range(0, len(records), batch_size):
            batch = records[i:i + batch_size]
            data = [[r.timestamp, r.account, r.product, r.metric_value,
                     r.metric_count, r.category, r.region, r.status,
                     r.description, r.extra_data] for r in batch]
            self.client.insert(table, data, column_names=columns)
        return time.time() - start
    
    def verify_pipeline(self, expected_unique: int):
        print("\n[검증] 파이프라인 데이터 검증")
        
        landing = self.client.command("SELECT count() FROM dedup.p3_landing")
        main_raw = self.client.command("SELECT count() FROM dedup.p3_main")
        main_final = self.client.command("SELECT count() FROM dedup.p3_main FINAL")
        
        print(f"Landing: {landing}, Main(raw): {main_raw}, Main(FINAL): {main_final}")
        print(f"Expected unique: {expected_unique}")
        
        if main_final == expected_unique:
            print("✅ Main FINAL = Expected")
        else:
            print("❌ Main FINAL ≠ Expected")
    
    def force_refresh_mvs(self):
        self.client.command("SYSTEM REFRESH VIEW dedup.p3_hourly_agg")
        time.sleep(5)
        self.client.command("SYSTEM REFRESH VIEW dedup.p3_daily_agg")
        time.sleep(5)

def run_phase3():
    config = TestConfig()
    tester = Phase3Tester(config)
    generator = DataGenerator(config)
    
    print("=" * 60)
    print("Phase 3: 권장 아키텍처 검증")
    print("=" * 60)
    
    records, expected_unique = generator.generate()
    tester.insert_to_landing(records)
    
    print("MV Refresh 대기 (70초)...")
    time.sleep(70)
    tester.force_refresh_mvs()
    tester.verify_pipeline(expected_unique)

if __name__ == '__main__':
    run_phase3()
```

---

## 7. Phase 4: Cascading MV 정합성

### 7.1 목적

일반 MV vs Refreshable MV 체인에서 중복 데이터 전파 여부를 비교한다.

### 7.2 테이블 생성 DDL

```sql
-- 4A: 일반 MV 체인 (문제 케이스)
CREATE TABLE dedup.p4a_source (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64
) ENGINE = ReplacingMergeTree()
ORDER BY (timestamp, account, product);

CREATE MATERIALIZED VIEW dedup.p4a_hourly_mv
ENGINE = SummingMergeTree() ORDER BY (hour, account)
AS SELECT 
    toStartOfHour(timestamp) as hour, account,
    count() as event_count, sum(metric_value) as total_value
FROM dedup.p4a_source
GROUP BY hour, account;

-- 4B: Refreshable MV 체인 (권장)
CREATE TABLE dedup.p4b_source (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64
) ENGINE = ReplacingMergeTree()
ORDER BY (timestamp, account, product);

CREATE MATERIALIZED VIEW dedup.p4b_hourly_mv
REFRESH EVERY 1 MINUTE
ENGINE = MergeTree() ORDER BY (hour, account)
AS SELECT 
    toStartOfHour(timestamp) as hour, account,
    count() as event_count, sum(metric_value) as total_value
FROM dedup.p4b_source FINAL
GROUP BY hour, account;
```

### 7.3 예상 결과 비교

| 항목 | 일반 MV | Refreshable MV |
|------|---------|----------------|
| Source FINAL | 10,000 | 10,000 |
| Hourly count | 13,000 (중복!) | 10,000 |
| Hourly value | 부풀려짐 | 정확 |

---

## 8. Phase 5: 부하 테스트

### 8.1 테이블 생성 DDL

```sql
CREATE TABLE dedup.p5_landing (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    _insert_time DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
ORDER BY (timestamp, account, product)
TTL toDateTime(_insert_time) + INTERVAL 2 HOUR;

CREATE TABLE dedup.p5_main (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    _version UInt64
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (timestamp, account, product);

CREATE MATERIALIZED VIEW dedup.p5_landing_to_main_mv TO dedup.p5_main AS
SELECT *, toUInt64(now64(3)) as _version FROM dedup.p5_landing;

CREATE MATERIALIZED VIEW dedup.p5_realtime_agg
REFRESH EVERY 30 SECOND
ENGINE = MergeTree() ORDER BY (minute, account)
AS SELECT 
    toStartOfMinute(timestamp) as minute, account,
    count() as events, uniq(timestamp, product) as unique_events
FROM dedup.p5_main FINAL
GROUP BY minute, account;
```

### 8.2 테스트 스크립트

```python
#!/usr/bin/env python3
"""
Phase 5: 부하 테스트
파일명: phase5_load_test.py
"""

import clickhouse_connect
import time
import random
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor
from phase1_engine_comparison import TestConfig

class LoadTestRunner:
    def __init__(self, config: TestConfig):
        self.config = config
        self.running = True
        self.insert_count = 0
        self.query_count = 0
        self.errors = []
        
    def get_client(self):
        return clickhouse_connect.get_client(
            host=self.config.host, port=self.config.port,
            username=self.config.username, password=self.config.password,
            database=self.config.database, secure=True
        )
    
    def insert_worker(self, worker_id: int, duration_sec: int):
        client = self.get_client()
        end_time = time.time() + duration_sec
        
        while time.time() < end_time and self.running:
            try:
                ts = datetime.now() - timedelta(seconds=random.randint(0, 300))
                account = f'account_{random.randint(1, 100):04d}'
                product = f'product_{random.randint(1, 50):03d}'
                
                if random.random() < 0.3:
                    ts = ts.replace(microsecond=0)
                
                sql = f"""INSERT INTO dedup.p5_landing 
                    (timestamp, account, product, metric_value, metric_count, category)
                    VALUES ('{ts.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}',
                        '{account}', '{product}', {random.random() * 1000},
                        {random.randint(1, 100)}, '{random.choice(['A', 'B', 'C'])}')"""
                client.command(sql)
                self.insert_count += 1
            except Exception as e:
                self.errors.append(f"Insert error: {e}")
            time.sleep(0.01)
    
    def query_worker(self, worker_id: int, duration_sec: int):
        client = self.get_client()
        end_time = time.time() + duration_sec
        queries = [
            "SELECT count() FROM dedup.p5_main FINAL",
            "SELECT account, sum(unique_events) FROM dedup.p5_realtime_agg GROUP BY account LIMIT 10",
        ]
        
        while time.time() < end_time and self.running:
            try:
                client.query(random.choice(queries))
                self.query_count += 1
            except Exception as e:
                self.errors.append(f"Query error: {e}")
            time.sleep(0.5)
    
    def monitor_worker(self, duration_sec: int):
        client = self.get_client()
        end_time = time.time() + duration_sec
        
        print(f"{'Time':<8} {'Inserts':<10} {'Queries':<10} {'Main FINAL':<12}")
        while time.time() < end_time and self.running:
            try:
                main_final = client.command("SELECT count() FROM dedup.p5_main FINAL")
                elapsed = int(time.time() - (end_time - duration_sec))
                print(f"{elapsed:<8} {self.insert_count:<10} {self.query_count:<10} {main_final:<12}")
            except:
                pass
            time.sleep(10)
    
    def run(self, duration_sec: int = 120, insert_workers: int = 3, query_workers: int = 2):
        print(f"부하 테스트 시작: {duration_sec}초")
        
        with ThreadPoolExecutor(max_workers=insert_workers + query_workers + 1) as executor:
            for i in range(insert_workers):
                executor.submit(self.insert_worker, i, duration_sec)
            for i in range(query_workers):
                executor.submit(self.query_worker, i, duration_sec)
            executor.submit(self.monitor_worker, duration_sec)
        
        print(f"\n총 Insert: {self.insert_count}, 총 Query: {self.query_count}, 에러: {len(self.errors)}")

def run_phase5():
    config = TestConfig()
    runner = LoadTestRunner(config)
    runner.run(duration_sec=120, insert_workers=3, query_workers=2)

if __name__ == '__main__':
    run_phase5()
```

---

## 9. 모니터링 쿼리

### 9.1 Part 상태

```sql
SELECT table, count() as parts, sum(rows) as total_rows,
       formatReadableSize(sum(bytes_on_disk)) as size
FROM system.parts
WHERE database = 'dedup' AND active
GROUP BY table ORDER BY table;
```

### 9.2 MV Refresh 상태

```sql
SELECT database, view, status, last_refresh_result, 
       last_refresh_time, next_refresh_time
FROM system.view_refreshes
WHERE database = 'dedup';
```

### 9.3 쿼리 성능 비교

```sql
-- FINAL
SELECT count() FROM dedup.p3_main FINAL;

-- Subquery
SELECT count() FROM (
    SELECT timestamp, account, product
    FROM dedup.p3_main GROUP BY timestamp, account, product
);

-- argMax
SELECT timestamp, account, product, argMax(metric_value, _version)
FROM dedup.p3_main GROUP BY timestamp, account, product;
```

---

## 10. Cleanup

```sql
-- Phase 1
DROP TABLE IF EXISTS dedup.p1_baseline;
DROP TABLE IF EXISTS dedup.p1_replacing;
DROP TABLE IF EXISTS dedup.p1_collapsing;
DROP TABLE IF EXISTS dedup.p1_aggregating;

-- Phase 2
DROP TABLE IF EXISTS dedup.p2_row_by_row;
DROP TABLE IF EXISTS dedup.p2_micro_batch;
DROP TABLE IF EXISTS dedup.p2_batch;
DROP TABLE IF EXISTS dedup.p2_async_insert;

-- Phase 3
DROP VIEW IF EXISTS dedup.p3_daily_agg;
DROP VIEW IF EXISTS dedup.p3_hourly_agg;
DROP VIEW IF EXISTS dedup.p3_landing_to_main_mv;
DROP TABLE IF EXISTS dedup.p3_main;
DROP TABLE IF EXISTS dedup.p3_landing;

-- Phase 4
DROP VIEW IF EXISTS dedup.p4a_hourly_mv;
DROP TABLE IF EXISTS dedup.p4a_source;
DROP VIEW IF EXISTS dedup.p4b_hourly_mv;
DROP TABLE IF EXISTS dedup.p4b_source;

-- Phase 5
DROP VIEW IF EXISTS dedup.p5_realtime_agg;
DROP VIEW IF EXISTS dedup.p5_landing_to_main_mv;
DROP TABLE IF EXISTS dedup.p5_main;
DROP TABLE IF EXISTS dedup.p5_landing;
```

---

## 11. 결론 및 권장사항

### 11.1 Engine 선택

| Engine | Dedup 효과 | 구현 복잡도 | MV 호환성 | 권장 |
|--------|-----------|------------|-----------|------|
| ReplacingMergeTree | ✅ 우수 | 낮음 | FINAL 필요 | ⭐ 권장 |
| CollapsingMergeTree | ⚠️ 조건부 | 높음 | 복잡 | ❌ 비권장 |
| AggregatingMergeTree | ✅ 우수 | 중간 | 복잡 | ⚠️ 조건부 |

### 11.2 권장 아키텍처

```
[Java App] → [Landing Table] → [Main Table] → [Refreshable MVs]
             (MergeTree+TTL)   (ReplacingMT)   (FINAL 사용)
```

### 11.3 핵심 설정

```sql
SET async_insert = 1;
SET wait_for_async_insert = 0;
SET async_insert_busy_timeout_ms = 1000;
```

### 11.4 운영 체크리스트

- [ ] Async Insert 활성화
- [ ] TTL로 Landing 테이블 자동 정리
- [ ] Refreshable MV 주기 설정
- [ ] Part 개수 모니터링
- [ ] 쿼리에 FINAL 적용 확인

---

## 12. 참고 문서

- [ReplacingMergeTree](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [Refreshable Materialized Views](https://clickhouse.com/docs/en/materialized-view/refreshable-materialized-view)
- [Async Insert](https://clickhouse.com/docs/en/cloud/bestpractices/asynchronous-inserts)

---

**문서 끝**
