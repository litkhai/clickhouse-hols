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

첫째, 다양한 ClickHouse Table Engine의 deduplication 효과를 비교 분석한다. 둘째, Row-by-row insert 환경에서의 성능 영향을 측정한다. 셋째, Cascading Materialized View 환경에서 데이터 정합성을 확인한다. 넷째, 운영 환경 적용을 위한 최적 구성을 도출한다.

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
-- 테스트용 데이터베이스 생성
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
| 중복 패턴 | Random | 무작위 중복 발생 |

---

## 3. 테스트 시나리오 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                      테스트 시나리오 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 1: 기본 Engine 비교                                       │
│  ├── 1A: ReplacingMergeTree                                     │
│  ├── 1B: CollapsingMergeTree                                    │
│  └── 1C: AggregatingMergeTree                                   │
│                                                                 │
│  Phase 2: Insert 패턴별 성능                                      │
│  ├── 2A: Row-by-row (고객 현재 방식)                              │
│  ├── 2B: Micro-batch (100 rows)                                 │
│  └── 2C: Batch (1,000+ rows)                                    │
│                                                                 │
│  Phase 3: 권장 아키텍처 검증                                       │
│  ├── 3A: Landing → Main (RMT) 구조                              │
│  └── 3B: Async Insert 효과                                       │
│                                                                 │
│  Phase 4: Cascading MV 정합성                                    │
│  ├── 4A: 일반 MV 체인                                            │
│  └── 4B: Refreshable MV 체인                                    │
│                                                                 │
│  Phase 5: 부하 테스트                                             │
│  └── 5A: 지속적 insert + 동시 쿼리                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Phase 1: 기본 Engine 비교

### 4.1 목적

동일한 중복 데이터에 대해 각 Table Engine의 deduplication 동작 방식과 효과를 비교한다.

### 4.2 테이블 생성 DDL

#### 4.2.1 베이스라인 (일반 MergeTree)

```sql
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
ORDER BY (timestamp, account, product)
SETTINGS index_granularity = 8192;
```

#### 4.2.2 ReplacingMergeTree

```sql
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
ORDER BY (timestamp, account, product)
SETTINGS index_granularity = 8192;
```

#### 4.2.3 CollapsingMergeTree

```sql
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
ORDER BY (timestamp, account, product)
SETTINGS index_granularity = 8192;
```

#### 4.2.4 AggregatingMergeTree

```sql
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
    extra_data SimpleAggregateFunction(any, String),
    _row_count AggregateFunction(count, UInt64)
) ENGINE = AggregatingMergeTree()
ORDER BY (timestamp, account, product)
SETTINGS index_granularity = 8192;
```

### 4.3 테스트 실행 스크립트

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
from typing import List, Dict, Tuple
import json

# ============================================
# 설정
# ============================================
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

# ============================================
# 데이터 생성기
# ============================================
class DataGenerator:
    CATEGORIES = ['electronics', 'clothing', 'food', 'furniture', 'sports']
    REGIONS = ['asia', 'europe', 'americas', 'oceania', 'africa']
    STATUSES = ['active', 'pending', 'completed', 'cancelled']
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.base_time = datetime.now() - timedelta(hours=1)
        
    def generate(self) -> Tuple[List[TestRecord], int]:
        """중복 포함 데이터 생성, unique 개수 반환"""
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
        
        # 중복 추가
        num_dup = int(len(unique_records) * self.config.duplicate_rate)
        duplicates = random.sample(unique_records, num_dup)
        all_records = unique_records + duplicates
        random.shuffle(all_records)
        
        return all_records, len(unique_records)

# ============================================
# 테스트 실행기
# ============================================
class Phase1Tester:
    def __init__(self, config: TestConfig):
        self.config = config
        self.client = clickhouse_connect.get_client(
            host=config.host,
            port=config.port,
            username=config.username,
            password=config.password,
            database=config.database,
            secure=True
        )
        
    def insert_batch(self, table: str, records: List[TestRecord]) -> float:
        """배치 insert (효율적 테스트용)"""
        columns = ['timestamp', 'account', 'product', 'metric_value', 
                   'metric_count', 'category', 'region', 'status', 
                   'description', 'extra_data']
        
        data = [[
            r.timestamp, r.account, r.product, r.metric_value,
            r.metric_count, r.category, r.region, r.status,
            r.description, r.extra_data
        ] for r in records]
        
        start = time.time()
        self.client.insert(table, data, column_names=columns)
        return time.time() - start
    
    def insert_row_by_row(self, table: str, records: List[TestRecord], 
                          limit: int = 1000) -> float:
        """Row-by-row insert (고객 환경 시뮬레이션)"""
        start = time.time()
        
        for i, r in enumerate(records[:limit]):
            sql = f"""
                INSERT INTO {table} 
                (timestamp, account, product, metric_value, metric_count,
                 category, region, status, description, extra_data)
                VALUES (
                    '{r.timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}',
                    '{r.account}', '{r.product}', {r.metric_value},
                    {r.metric_count}, '{r.category}', '{r.region}',
                    '{r.status}', '{r.description}', '{r.extra_data}'
                )
            """
            self.client.command(sql)
            
            if (i + 1) % 100 == 0:
                print(f"  Inserted {i + 1} rows...")
                
        return time.time() - start
    
    def verify_counts(self, table: str, engine_type: str) -> Dict:
        """Dedup 결과 검증"""
        result = {'table': table, 'engine': engine_type}
        
        # 총 row 수 (merge 전)
        result['raw_count'] = self.client.command(
            f"SELECT count() FROM {table}"
        )
        
        # Dedup된 row 수
        if engine_type in ['replacing', 'collapsing', 'aggregating']:
            result['dedup_count'] = self.client.command(
                f"SELECT count() FROM {table} FINAL"
            )
        else:
            result['dedup_count'] = self.client.command(
                f"SELECT count(DISTINCT (timestamp, account, product)) FROM {table}"
            )
        
        # OPTIMIZE 후
        self.client.command(f"OPTIMIZE TABLE {table} FINAL")
        time.sleep(2)
        result['after_optimize'] = self.client.command(
            f"SELECT count() FROM {table}"
        )
        
        return result
    
    def get_storage_info(self, table: str) -> Dict:
        """스토리지 정보 조회"""
        result = self.client.query(f"""
            SELECT 
                sum(rows) as rows,
                sum(bytes_on_disk) as bytes,
                count() as parts
            FROM system.parts
            WHERE database = '{self.config.database}'
              AND table = '{table}'
              AND active
        """)
        
        if result.result_rows:
            row = result.result_rows[0]
            return {
                'rows': row[0],
                'bytes': row[1],
                'parts': row[2],
                'bytes_readable': f"{row[1] / 1024 / 1024:.2f} MB"
            }
        return {}

# ============================================
# 실행
# ============================================
def run_phase1():
    config = TestConfig()
    tester = Phase1Tester(config)
    generator = DataGenerator(config)
    
    print("=" * 60)
    print("Phase 1: Engine 비교 테스트")
    print("=" * 60)
    
    # 데이터 생성
    print("\n[1] 테스트 데이터 생성...")
    records, expected_unique = generator.generate()
    print(f"    총 레코드: {len(records)}")
    print(f"    예상 Unique: {expected_unique}")
    print(f"    중복 레코드: {len(records) - expected_unique}")
    
    # 테이블별 테스트
    tables = [
        ('dedup.p1_baseline', 'baseline'),
        ('dedup.p1_replacing', 'replacing'),
        ('dedup.p1_collapsing', 'collapsing'),
        ('dedup.p1_aggregating', 'aggregating'),
    ]
    
    results = []
    
    for table, engine in tables:
        print(f"\n[2] Testing {table}...")
        
        # Insert
        elapsed = tester.insert_batch(table, records)
        print(f"    Insert 완료: {elapsed:.2f}초")
        
        # 검증
        counts = tester.verify_counts(table, engine)
        storage = tester.get_storage_info(table.split('.')[1])
        
        results.append({
            **counts,
            **storage,
            'insert_time': elapsed
        })
        
        print(f"    Raw count: {counts['raw_count']}")
        print(f"    Dedup count: {counts['dedup_count']}")
        print(f"    After OPTIMIZE: {counts['after_optimize']}")
        print(f"    Storage: {storage.get('bytes_readable', 'N/A')}")
    
    # 결과 요약
    print("\n" + "=" * 60)
    print("Phase 1 결과 요약")
    print("=" * 60)
    print(f"{'Engine':<15} {'Raw':<10} {'Dedup':<10} {'Optimized':<10} {'Storage':<12}")
    print("-" * 60)
    for r in results:
        print(f"{r['engine']:<15} {r['raw_count']:<10} {r['dedup_count']:<10} "
              f"{r['after_optimize']:<10} {r.get('bytes_readable', 'N/A'):<12}")
    
    return results

if __name__ == '__main__':
    run_phase1()
```

### 4.4 예상 결과 및 평가 기준

| Engine | Raw Count | Dedup Count | OPTIMIZE 후 | 평가 |
|--------|-----------|-------------|-------------|------|
| baseline | 13,000 | 10,000 (DISTINCT) | 13,000 | 중복 유지 |
| replacing | 13,000 | 10,000 (FINAL) | 10,000 | ✅ Dedup 성공 |
| collapsing | 13,000 | 13,000 | 13,000 | ❌ Sign 관리 필요 |
| aggregating | 13,000 | 10,000 (FINAL) | 10,000 | ✅ Dedup 성공 |

---

## 5. Phase 2: Insert 패턴별 성능

### 5.1 목적

Row-by-row vs Batch insert의 성능 차이를 측정하고, 고객 환경에서의 최적화 가능성을 평가한다.

### 5.2 테이블 생성 DDL

```sql
-- Phase 2용 ReplacingMergeTree (권장 엔진)
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

### 5.3 테스트 실행 스크립트

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
            host=config.host,
            port=config.port,
            username=config.username,
            password=config.password,
            database=config.database,
            secure=True
        )
    
    def test_row_by_row(self, records: List[TestRecord], limit: int = 1000):
        """2A: Row-by-row insert (고객 현재 방식)"""
        table = 'dedup.p2_row_by_row'
        print(f"\n[2A] Row-by-row insert ({limit} records)...")
        
        start = time.time()
        for i, r in enumerate(records[:limit]):
            sql = f"""
                INSERT INTO {table} 
                (timestamp, account, product, metric_value, metric_count,
                 category, region, status, description, extra_data)
                VALUES (
                    '{r.timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}',
                    '{r.account}', '{r.product}', {r.metric_value},
                    {r.metric_count}, '{r.category}', '{r.region}',
                    '{r.status}', '{r.description}', '{r.extra_data}'
                )
            """
            self.client.command(sql)
            
        elapsed = time.time() - start
        rate = limit / elapsed
        
        print(f"    완료: {elapsed:.2f}초 ({rate:.1f} rows/sec)")
        return {'method': 'row_by_row', 'records': limit, 
                'elapsed': elapsed, 'rate': rate}
    
    def test_micro_batch(self, records: List[TestRecord], 
                         batch_size: int = 100, limit: int = 10000):
        """2B: Micro-batch insert"""
        table = 'dedup.p2_micro_batch'
        print(f"\n[2B] Micro-batch insert (batch={batch_size}, total={limit})...")
        
        columns = ['timestamp', 'account', 'product', 'metric_value', 
                   'metric_count', 'category', 'region', 'status', 
                   'description', 'extra_data']
        
        start = time.time()
        for i in range(0, min(limit, len(records)), batch_size):
            batch = records[i:i + batch_size]
            data = [[
                r.timestamp, r.account, r.product, r.metric_value,
                r.metric_count, r.category, r.region, r.status,
                r.description, r.extra_data
            ] for r in batch]
            self.client.insert(table, data, column_names=columns)
            
        elapsed = time.time() - start
        rate = limit / elapsed
        
        print(f"    완료: {elapsed:.2f}초 ({rate:.1f} rows/sec)")
        return {'method': 'micro_batch', 'batch_size': batch_size,
                'records': limit, 'elapsed': elapsed, 'rate': rate}
    
    def test_batch(self, records: List[TestRecord], limit: int = 10000):
        """2C: Full batch insert"""
        table = 'dedup.p2_batch'
        print(f"\n[2C] Full batch insert ({limit} records)...")
        
        columns = ['timestamp', 'account', 'product', 'metric_value', 
                   'metric_count', 'category', 'region', 'status', 
                   'description', 'extra_data']
        
        data = [[
            r.timestamp, r.account, r.product, r.metric_value,
            r.metric_count, r.category, r.region, r.status,
            r.description, r.extra_data
        ] for r in records[:limit]]
        
        start = time.time()
        self.client.insert(table, data, column_names=columns)
        elapsed = time.time() - start
        rate = limit / elapsed
        
        print(f"    완료: {elapsed:.2f}초 ({rate:.1f} rows/sec)")
        return {'method': 'batch', 'records': limit, 
                'elapsed': elapsed, 'rate': rate}
    
    def test_async_insert(self, records: List[TestRecord], limit: int = 1000):
        """2D: Async insert (row-by-row with async)"""
        table = 'dedup.p2_async_insert'
        print(f"\n[2D] Async row-by-row insert ({limit} records)...")
        
        # Async insert 설정
        self.client.command("SET async_insert = 1")
        self.client.command("SET wait_for_async_insert = 0")
        
        start = time.time()
        for i, r in enumerate(records[:limit]):
            sql = f"""
                INSERT INTO {table} 
                (timestamp, account, product, metric_value, metric_count,
                 category, region, status, description, extra_data)
                VALUES (
                    '{r.timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}',
                    '{r.account}', '{r.product}', {r.metric_value},
                    {r.metric_count}, '{r.category}', '{r.region}',
                    '{r.status}', '{r.description}', '{r.extra_data}'
                )
            """
            self.client.command(sql)
            
        elapsed = time.time() - start
        rate = limit / elapsed
        
        # 설정 복원
        self.client.command("SET async_insert = 0")
        
        print(f"    완료: {elapsed:.2f}초 ({rate:.1f} rows/sec)")
        return {'method': 'async_insert', 'records': limit, 
                'elapsed': elapsed, 'rate': rate}
    
    def verify_all_tables(self, expected_unique: int):
        """모든 테이블 검증"""
        tables = ['p2_row_by_row', 'p2_micro_batch', 'p2_batch', 'p2_async_insert']
        
        print("\n[검증] Dedup 결과:")
        for t in tables:
            raw = self.client.command(f"SELECT count() FROM dedup.{t}")
            dedup = self.client.command(f"SELECT count() FROM dedup.{t} FINAL")
            print(f"    {t}: raw={raw}, dedup={dedup}, expected={expected_unique}")

def run_phase2():
    config = TestConfig()
    tester = Phase2Tester(config)
    generator = DataGenerator(config)
    
    print("=" * 60)
    print("Phase 2: Insert 패턴 성능 테스트")
    print("=" * 60)
    
    # 데이터 생성
    records, expected_unique = generator.generate()
    print(f"테스트 데이터: {len(records)} records ({expected_unique} unique)")
    
    results = []
    
    # 테스트 실행
    results.append(tester.test_row_by_row(records, limit=1000))
    results.append(tester.test_micro_batch(records, batch_size=100, limit=10000))
    results.append(tester.test_batch(records, limit=10000))
    results.append(tester.test_async_insert(records, limit=1000))
    
    # 검증
    tester.verify_all_tables(expected_unique)
    
    # 결과 요약
    print("\n" + "=" * 60)
    print("Phase 2 결과 요약")
    print("=" * 60)
    print(f"{'Method':<20} {'Records':<10} {'Time(s)':<10} {'Rate(r/s)':<12}")
    print("-" * 60)
    for r in results:
        print(f"{r['method']:<20} {r['records']:<10} {r['elapsed']:<10.2f} {r['rate']:<12.1f}")
    
    return results

if __name__ == '__main__':
    run_phase2()
```

### 5.4 예상 결과

| Method | Records | Time (s) | Rate (rows/s) | 비고 |
|--------|---------|----------|---------------|------|
| row_by_row | 1,000 | ~30-60 | ~15-30 | 매우 느림 |
| micro_batch | 10,000 | ~5-10 | ~1,000-2,000 | 개선됨 |
| batch | 10,000 | ~1-2 | ~5,000-10,000 | 가장 빠름 |
| async_insert | 1,000 | ~10-20 | ~50-100 | 개선됨 |

---

## 6. Phase 3: 권장 아키텍처 검증

### 6.1 목적

Landing 테이블 + ReplacingMergeTree + Refreshable MV 구조의 효과를 검증한다.

### 6.2 아키텍처 다이어그램

```
┌──────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Java App    │────▶│  p3_landing     │────▶│  p3_main        │
│ (row-by-row) │     │  (MergeTree)    │ MV  │  (ReplacingMT)  │
└──────────────┘     │  TTL 1 hour     │     └────────┬────────┘
                     └─────────────────┘              │
                                                      │ Refreshable MV
                                                      ▼
                                          ┌─────────────────────┐
                                          │  p3_hourly_agg      │
                                          │  (MergeTree)        │
                                          └──────────┬──────────┘
                                                     │ Refreshable MV
                                                     ▼
                                          ┌─────────────────────┐
                                          │  p3_daily_agg       │
                                          │  (MergeTree)        │
                                          └─────────────────────┘
```

### 6.3 테이블 생성 DDL

```sql
-- 1. Landing 테이블 (TTL 1시간)
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
TTL toDateTime(_insert_time) + INTERVAL 1 HOUR
SETTINGS index_granularity = 8192;

-- 2. Main 테이블 (ReplacingMergeTree)
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
ORDER BY (timestamp, account, product)
SETTINGS index_granularity = 8192;

-- 3. Landing → Main MV
CREATE MATERIALIZED VIEW dedup.p3_landing_to_main_mv
TO dedup.p3_main AS
SELECT 
    timestamp,
    account,
    product,
    metric_value,
    metric_count,
    category,
    region,
    status,
    description,
    extra_data,
    toUInt64(now64(3)) as _version
FROM dedup.p3_landing;

-- 4. Hourly Aggregation (Refreshable MV)
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
    sum(metric_value) as total_metric_value,
    sum(metric_count) as total_metric_count
FROM dedup.p3_main FINAL
GROUP BY hour, account, category;

-- 5. Daily Aggregation (Refreshable MV, depends on hourly)
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

### 6.4 테스트 실행 스크립트

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
            host=config.host,
            port=config.port,
            username=config.username,
            password=config.password,
            database=config.database,
            secure=True
        )
    
    def insert_to_landing(self, records, batch_size=1000):
        """Landing 테이블로 insert"""
        table = 'dedup.p3_landing'
        columns = ['timestamp', 'account', 'product', 'metric_value', 
                   'metric_count', 'category', 'region', 'status', 
                   'description', 'extra_data']
        
        print(f"\n[Insert] Landing 테이블로 {len(records)} records insert...")
        
        start = time.time()
        for i in range(0, len(records), batch_size):
            batch = records[i:i + batch_size]
            data = [[
                r.timestamp, r.account, r.product, r.metric_value,
                r.metric_count, r.category, r.region, r.status,
                r.description, r.extra_data
            ] for r in batch]
            self.client.insert(table, data, column_names=columns)
        
        elapsed = time.time() - start
        print(f"    완료: {elapsed:.2f}초")
        return elapsed
    
    def wait_for_mv_refresh(self, seconds=70):
        """Refreshable MV 갱신 대기"""
        print(f"\n[대기] MV Refresh 대기 ({seconds}초)...")
        time.sleep(seconds)
    
    def verify_pipeline(self, expected_unique: int):
        """파이프라인 전체 검증"""
        print("\n[검증] 파이프라인 데이터 검증")
        print("-" * 50)
        
        # Landing
        landing = self.client.command("SELECT count() FROM dedup.p3_landing")
        print(f"Landing: {landing} rows")
        
        # Main (raw vs dedup)
        main_raw = self.client.command("SELECT count() FROM dedup.p3_main")
        main_final = self.client.command("SELECT count() FROM dedup.p3_main FINAL")
        print(f"Main (raw): {main_raw} rows")
        print(f"Main (FINAL): {main_final} rows")
        print(f"Expected unique: {expected_unique}")
        
        # Hourly aggregation
        hourly_unique = self.client.command(
            "SELECT sum(unique_events) FROM dedup.p3_hourly_agg"
        )
        print(f"Hourly agg unique_events sum: {hourly_unique}")
        
        # Daily aggregation
        daily_unique = self.client.command(
            "SELECT sum(daily_unique_events) FROM dedup.p3_daily_agg"
        )
        print(f"Daily agg unique_events sum: {daily_unique}")
        
        # 정합성 체크
        print("\n[정합성 체크]")
        if main_final == expected_unique:
            print(f"  ✅ Main FINAL = Expected ({main_final} = {expected_unique})")
        else:
            print(f"  ❌ Main FINAL ≠ Expected ({main_final} ≠ {expected_unique})")
            
        if hourly_unique == expected_unique:
            print(f"  ✅ Hourly = Expected ({hourly_unique} = {expected_unique})")
        else:
            print(f"  ⚠️  Hourly ≠ Expected ({hourly_unique} ≠ {expected_unique})")
            print(f"      (uniq 함수 특성상 근사값일 수 있음)")
    
    def force_refresh_mvs(self):
        """강제 MV 리프레시"""
        print("\n[Refresh] MV 강제 리프레시...")
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
    
    # 데이터 생성
    records, expected_unique = generator.generate()
    print(f"테스트 데이터: {len(records)} records ({expected_unique} unique)")
    
    # Landing 테이블로 insert
    tester.insert_to_landing(records)
    
    # MV 리프레시 대기
    tester.wait_for_mv_refresh(70)
    
    # 강제 리프레시 (확실한 검증용)
    tester.force_refresh_mvs()
    
    # 검증
    tester.verify_pipeline(expected_unique)
    
    print("\n" + "=" * 60)
    print("Phase 3 완료")
    print("=" * 60)

if __name__ == '__main__':
    run_phase3()
```

---

## 7. Phase 4: Cascading MV 정합성

### 7.1 목적

일반 MV vs Refreshable MV 체인에서 중복 데이터 전파 여부를 비교 검증한다.

### 7.2 테이블 생성 DDL

#### 7.2.1 일반 MV 체인 (문제 케이스)

```sql
-- Source 테이블
CREATE TABLE dedup.p4a_source (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64
) ENGINE = ReplacingMergeTree()
ORDER BY (timestamp, account, product);

-- 일반 MV → Hourly (중복 전파됨!)
CREATE MATERIALIZED VIEW dedup.p4a_hourly_mv
ENGINE = SummingMergeTree()
ORDER BY (hour, account)
AS SELECT 
    toStartOfHour(timestamp) as hour,
    account,
    count() as event_count,
    sum(metric_value) as total_value
FROM dedup.p4a_source
GROUP BY hour, account;

-- 일반 MV → Daily (중복이 누적됨!)
CREATE MATERIALIZED VIEW dedup.p4a_daily_mv
ENGINE = SummingMergeTree()
ORDER BY (day, account)
AS SELECT 
    toDate(hour) as day,
    account,
    sum(event_count) as daily_count,
    sum(total_value) as daily_value
FROM dedup.p4a_hourly_mv
GROUP BY day, account;
```

#### 7.2.2 Refreshable MV 체인 (권장)

```sql
-- Source 테이블 (동일)
CREATE TABLE dedup.p4b_source (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64
) ENGINE = ReplacingMergeTree()
ORDER BY (timestamp, account, product);

-- Refreshable MV → Hourly (FINAL로 dedup된 데이터 사용)
CREATE MATERIALIZED VIEW dedup.p4b_hourly_mv
REFRESH EVERY 1 MINUTE
ENGINE = MergeTree()
ORDER BY (hour, account)
AS SELECT 
    toStartOfHour(timestamp) as hour,
    account,
    count() as event_count,
    sum(metric_value) as total_value
FROM dedup.p4b_source FINAL
GROUP BY hour, account;

-- Refreshable MV → Daily
CREATE MATERIALIZED VIEW dedup.p4b_daily_mv
REFRESH EVERY 5 MINUTE DEPENDS ON dedup.p4b_hourly_mv
ENGINE = MergeTree()
ORDER BY (day, account)
AS SELECT 
    toDate(hour) as day,
    account,
    sum(event_count) as daily_count,
    sum(total_value) as daily_value
FROM dedup.p4b_hourly_mv
GROUP BY day, account;
```

### 7.3 테스트 실행 스크립트

```python
#!/usr/bin/env python3
"""
Phase 4: Cascading MV 정합성 테스트
파일명: phase4_cascading_mv.py
"""

import clickhouse_connect
import time
from phase1_engine_comparison import TestConfig, DataGenerator

class Phase4Tester:
    def __init__(self, config: TestConfig):
        self.config = config
        self.client = clickhouse_connect.get_client(
            host=config.host,
            port=config.port,
            username=config.username,
            password=config.password,
            database=config.database,
            secure=True
        )
    
    def insert_test_data(self, records, table_prefix):
        """테스트 데이터 insert"""
        table = f'dedup.{table_prefix}_source'
        columns = ['timestamp', 'account', 'product', 'metric_value']
        
        data = [[r.timestamp, r.account, r.product, r.metric_value] 
                for r in records]
        
        print(f"  Insert to {table}...")
        self.client.insert(table, data, column_names=columns)
    
    def verify_regular_mv(self, expected_unique: int, expected_sum: float):
        """일반 MV 체인 검증"""
        print("\n[4A] 일반 MV 체인 검증")
        print("-" * 50)
        
        # Source
        source_raw = self.client.command("SELECT count() FROM dedup.p4a_source")
        source_final = self.client.command("SELECT count() FROM dedup.p4a_source FINAL")
        source_sum = self.client.command("SELECT sum(metric_value) FROM dedup.p4a_source FINAL")
        
        print(f"Source raw: {source_raw}")
        print(f"Source FINAL: {source_final}")
        print(f"Source sum(metric_value): {source_sum:.2f}")
        
        # Hourly MV (FINAL 없이 집계 → 중복 포함)
        hourly_count = self.client.command("SELECT sum(event_count) FROM dedup.p4a_hourly_mv FINAL")
        hourly_sum = self.client.command("SELECT sum(total_value) FROM dedup.p4a_hourly_mv FINAL")
        
        print(f"Hourly event_count sum: {hourly_count}")
        print(f"Hourly total_value sum: {hourly_sum:.2f}")
        
        # Daily MV
        daily_count = self.client.command("SELECT sum(daily_count) FROM dedup.p4a_daily_mv FINAL")
        daily_sum = self.client.command("SELECT sum(daily_value) FROM dedup.p4a_daily_mv FINAL")
        
        print(f"Daily event_count sum: {daily_count}")
        print(f"Daily total_value sum: {daily_sum:.2f}")
        
        # 정합성 체크
        print("\n[정합성]")
        if hourly_count > expected_unique:
            print(f"  ⚠️  Hourly에 중복 전파됨: {hourly_count} > {expected_unique}")
        if abs(hourly_sum - expected_sum) > 0.01:
            print(f"  ⚠️  Hourly sum 불일치: {hourly_sum:.2f} ≠ {expected_sum:.2f}")
    
    def verify_refreshable_mv(self, expected_unique: int, expected_sum: float):
        """Refreshable MV 체인 검증"""
        print("\n[4B] Refreshable MV 체인 검증")
        print("-" * 50)
        
        # 강제 리프레시
        self.client.command("SYSTEM REFRESH VIEW dedup.p4b_hourly_mv")
        time.sleep(10)
        self.client.command("SYSTEM REFRESH VIEW dedup.p4b_daily_mv")
        time.sleep(10)
        
        # Source
        source_final = self.client.command("SELECT count() FROM dedup.p4b_source FINAL")
        source_sum = self.client.command("SELECT sum(metric_value) FROM dedup.p4b_source FINAL")
        
        print(f"Source FINAL: {source_final}")
        print(f"Source sum(metric_value): {source_sum:.2f}")
        
        # Hourly MV
        hourly_count = self.client.command("SELECT sum(event_count) FROM dedup.p4b_hourly_mv")
        hourly_sum = self.client.command("SELECT sum(total_value) FROM dedup.p4b_hourly_mv")
        
        print(f"Hourly event_count sum: {hourly_count}")
        print(f"Hourly total_value sum: {hourly_sum:.2f}")
        
        # Daily MV
        daily_count = self.client.command("SELECT sum(daily_count) FROM dedup.p4b_daily_mv")
        daily_sum = self.client.command("SELECT sum(daily_value) FROM dedup.p4b_daily_mv")
        
        print(f"Daily event_count sum: {daily_count}")
        print(f"Daily total_value sum: {daily_sum:.2f}")
        
        # 정합성 체크
        print("\n[정합성]")
        if hourly_count == expected_unique:
            print(f"  ✅ Hourly count 일치: {hourly_count}")
        if abs(hourly_sum - expected_sum) < 0.01:
            print(f"  ✅ Hourly sum 일치: {hourly_sum:.2f}")

def run_phase4():
    config = TestConfig()
    config.total_unique_records = 5000  # 빠른 테스트용
    
    tester = Phase4Tester(config)
    generator = DataGenerator(config)
    
    print("=" * 60)
    print("Phase 4: Cascading MV 정합성 테스트")
    print("=" * 60)
    
    # 데이터 생성
    records, expected_unique = generator.generate()
    expected_sum = sum(r.metric_value for r in records[:expected_unique])
    
    print(f"테스트 데이터: {len(records)} records")
    print(f"Expected unique: {expected_unique}")
    print(f"Expected sum: {expected_sum:.2f}")
    
    # 4A: 일반 MV 테스트
    print("\n" + "=" * 60)
    tester.insert_test_data(records, 'p4a')
    time.sleep(5)
    tester.verify_regular_mv(expected_unique, expected_sum)
    
    # 4B: Refreshable MV 테스트
    print("\n" + "=" * 60)
    tester.insert_test_data(records, 'p4b')
    time.sleep(5)
    tester.verify_refreshable_mv(expected_unique, expected_sum)
    
    print("\n" + "=" * 60)
    print("Phase 4 완료")
    print("=" * 60)

if __name__ == '__main__':
    run_phase4()
```

### 7.4 예상 결과 비교

| 항목 | 일반 MV | Refreshable MV | 비고 |
|------|---------|----------------|------|
| Source FINAL | 10,000 | 10,000 | 동일 |
| Hourly count sum | 13,000 (중복!) | 10,000 | 일반 MV 문제 |
| Hourly value sum | 부풀려짐 | 정확 | 일반 MV 문제 |
| Daily count sum | 13,000 (중복!) | 10,000 | 일반 MV 문제 |

---

## 8. Phase 5: 부하 테스트

### 8.1 목적

실제 운영 환경을 시뮬레이션하여 지속적인 insert와 동시 쿼리 환경에서의 안정성을 검증한다.

### 8.2 테이블 생성 DDL

```sql
-- 부하 테스트용 테이블 (Phase 3 구조 재사용)
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

CREATE MATERIALIZED VIEW dedup.p5_landing_to_main_mv
TO dedup.p5_main AS
SELECT *, toUInt64(now64(3)) as _version
FROM dedup.p5_landing;

CREATE MATERIALIZED VIEW dedup.p5_realtime_agg
REFRESH EVERY 30 SECOND
ENGINE = MergeTree()
ORDER BY (minute, account)
AS SELECT 
    toStartOfMinute(timestamp) as minute,
    account,
    count() as events,
    uniq(timestamp, product) as unique_events
FROM dedup.p5_main FINAL
GROUP BY minute, account;
```

### 8.3 테스트 실행 스크립트

```python
#!/usr/bin/env python3
"""
Phase 5: 부하 테스트
파일명: phase5_load_test.py
"""

import clickhouse_connect
import time