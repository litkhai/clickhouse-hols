# ClickHouse Point Query 성능 최적화 가이드

**기반 테스트**: MySQL vs ClickHouse Point Query Benchmark
**목표**: Point Query 성능을 MySQL 수준으로 향상

---

## 📊 현재 성능 문제

현재 ClickHouse는 MySQL 대비 **약 54%의 성능**만 보이고 있습니다:

| 지표 | MySQL | ClickHouse (현재) | 비율 |
|------|-------|-------------------|------|
| 평균 QPS | 4,921 | 2,690 | 0.54x |
| P50 레이턴시 | 0.65ms | 3.95ms | 6.1배 느림 |

---

## 🎯 최적화 전략 로드맵

### Level 1: 기본 설정 최적화 (예상 향상: 20-30%)

#### 1.1 Index Granularity 최적화

**현재 설정**: `index_granularity = 8192` (기본값)

**문제점**: 8192는 OLAP 워크로드에 최적화되어 있으며, Point Query에는 너무 큼

**권장 설정**:
```sql
-- Point Query에 최적화된 index_granularity
CREATE TABLE player_last_login
(
    -- 컬럼 정의...
)
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS
    index_granularity = 256  -- 8192 → 256 (32배 작게)
```

**근거**:
- Altinity의 성능 테스트에 따르면, **key-value 조회 시 `index_granularity = 256`이 최적**
- UInt64 키의 경우 256이 최적, FixedString(16)의 경우 128도 고려
- 참조: [ClickHouse® In the Storm. Part 2: Maximum QPS for key-value lookups](https://altinity.com/blog/clickhouse-in-the-storm-part-2)

**트레이드오프**:
- ✅ Point Query 성능 향상: 약 2-3배
- ❌ 인덱스 크기 증가: 약 32배 (8192/256)
- ❌ 집계 쿼리 성능 약간 감소

---

#### 1.2 Bloom Filter Granularity 조정

**현재 설정**: `GRANULARITY 1`

**검토 필요**: 현재 설정이 최적인지 테스트 필요

**권장 접근**:
```sql
-- 옵션 1: GRANULARITY 1 유지 (현재)
INDEX idx_player_id_bloom player_id TYPE bloom_filter(0.01) GRANULARITY 1

-- 옵션 2: index_granularity와 동일하게 (테스트 필요)
INDEX idx_player_id_bloom player_id TYPE bloom_filter(0.01) GRANULARITY 1
```

**주의사항**:
- GRANULARITY 1은 가장 세밀한 필터링 제공
- `index_granularity`를 256으로 낮추면 Bloom Filter의 효과도 달라짐
- 참조: [ClickHouse® Black Magic, Part 2: Bloom Filters](https://altinity.com/blog/skipping-indices-part-2-bloom-filters)

---

#### 1.3 Adaptive Index Granularity 비활성화

**이유**: Point Query에는 고정된 작은 granularity가 더 효율적

```sql
SETTINGS
    index_granularity = 256,
    index_granularity_bytes = 0,  -- Adaptive 비활성화
    min_index_granularity_bytes = 0
```

**참조**: [Tuning Index Granularity in ClickHouse](https://chistadata.com/clickhouse-performance-index-granularity/)

---

### Level 2: 캐시 최적화 (예상 향상: 30-50%)

#### 2.1 Uncompressed Cache 활성화

**현재**: 비활성화 (기본값)

**권장 설정** (`config.xml`):
```xml
<clickhouse>
    <uncompressed_cache_size>5368709120</uncompressed_cache_size> <!-- 5GB -->
    <profiles>
        <default>
            <use_uncompressed_cache>1</use_uncompressed_cache>
        </default>
    </profiles>
</clickhouse>
```

**효과**:
- 짧고 빈번한 쿼리에 대해 **최대 50% 성능 향상**
- 압축 해제 시간 절약
- 참조: [Caching in ClickHouse® - The Definitive Guide Part 1](https://altinity.com/blog/caching-in-clickhouse-the-definitive-guide-part-1)

---

#### 2.2 Mark Cache 크기 증가

**권장 설정** (`config.xml`):
```xml
<clickhouse>
    <mark_cache_size>5368709120</mark_cache_size> <!-- 5GB -->
</clickhouse>
```

**효과**:
- 인덱스 메타데이터 캐싱으로 I/O 감소
- Point Query에서 매우 중요
- 참조: [Boost ClickHouse performance with mark cache](https://www.instaclustr.com/blog/boost-clickhouse-performance-with-mark-cache-a-complete-guide/)

---

#### 2.3 캐시 임계값 조정

```xml
<profiles>
    <default>
        <merge_tree_max_rows_to_use_cache>1000000</merge_tree_max_rows_to_use_cache>
        <merge_tree_max_bytes_to_use_cache>10485760</merge_tree_max_bytes_to_use_cache>
    </default>
</profiles>
```

**참조**: [Cache types | ClickHouse Docs](https://clickhouse.com/docs/operations/caches)

---

### Level 3: 쿼리 최적화 (예상 향상: 10-20%)

#### 3.1 PREWHERE 명시적 사용

**현재 쿼리**:
```sql
SELECT player_id, player_name, character_id, character_name,
       character_level, character_class, server_id, server_name,
       last_login_at, currency_gold, currency_diamond
FROM player_last_login
WHERE player_id = 12345
```

**최적화된 쿼리**:
```sql
SELECT player_id, player_name, character_id, character_name,
       character_level, character_class, server_id, server_name,
       last_login_at, currency_gold, currency_diamond
FROM player_last_login
PREWHERE player_id = 12345  -- WHERE → PREWHERE
```

**효과**:
- Primary Key 조건을 PREWHERE로 명시하면 더 적은 데이터 읽기
- I/O 최대 95% 감소 가능
- 쿼리 속도 17배 향상 사례 존재
- 참조: [How does the PREWHERE optimization work?](https://clickhouse.com/docs/optimize/prewhere)

---

#### 3.2 불필요한 컬럼 제거

**최적화**:
```sql
-- 필요한 컬럼만 SELECT
SELECT player_id, player_name, last_login_at
FROM player_last_login
PREWHERE player_id = 12345
```

**효과**:
- 컬럼 스토어의 특성상 읽는 컬럼 수가 성능에 직접 영향
- 11개 컬럼 → 3개 컬럼으로 줄이면 I/O 약 70% 감소

---

### Level 4: 테이블 엔진 변경 (예상 향상: 100-150%)

#### 4.1 Dictionary 엔진 사용

**가장 강력한 최적화**: MergeTree → Dictionary

**성능 비교**:
- MergeTree: 약 4,000 QPS
- Dictionary: 약 10,000 QPS (**2.5배 향상**)
- 참조: [ClickHouse® In the Storm. Part 2: Maximum QPS for key-value lookups](https://altinity.com/blog/clickhouse-in-the-storm-part-2)

**구현 방법**:

```sql
-- 1. MergeTree 테이블 유지 (쓰기용)
CREATE TABLE player_last_login_source
(
    player_id UInt64,
    player_name String,
    -- ... 기타 컬럼
)
ENGINE = MergeTree()
ORDER BY player_id;

-- 2. Dictionary 생성 (읽기용)
CREATE DICTIONARY player_last_login_dict
(
    player_id UInt64,
    player_name String,
    character_id UInt64,
    character_name String,
    character_level UInt16,
    character_class String,
    server_id UInt8,
    server_name String,
    last_login_at DateTime64(3),
    currency_gold UInt64,
    currency_diamond UInt32
)
PRIMARY KEY player_id
SOURCE(CLICKHOUSE(
    HOST 'localhost'
    PORT 9000
    USER 'default'
    PASSWORD ''
    DB 'gamedb'
    TABLE 'player_last_login_source'
))
LIFETIME(MIN 0 MAX 300)  -- 5분마다 갱신
LAYOUT(HASHED());  -- 또는 COMPLEX_KEY_HASHED()

-- 3. 쿼리 방법
SELECT
    dictGet('player_last_login_dict', 'player_name', toUInt64(12345)) AS player_name,
    dictGet('player_last_login_dict', 'character_name', toUInt64(12345)) AS character_name,
    dictGet('player_last_login_dict', 'last_login_at', toUInt64(12345)) AS last_login_at
```

**장점**:
- ✅ 2-3배 성능 향상
- ✅ 메모리 내 조회로 초저지연
- ✅ Primary Key 기반 O(1) 조회

**단점**:
- ❌ 메모리 사용량 증가 (200만 rows × 약 500 bytes = 약 1GB)
- ❌ 실시간 업데이트 불가 (LIFETIME 주기로 새로고침)
- ❌ 쿼리 구문 변경 필요

**참조**:
- [Using Dictionaries to Accelerate Queries](https://clickhouse.com/blog/faster-queries-dictionaries-clickhouse)
- [Simplifying Queries with ClickHouse Dictionaries](https://aggregations.io/blog/clickhouse-dictionaries)

---

#### 4.2 EmbeddedRocksDB 엔진 (대안)

**특징**: 진정한 Key-Value 스토어

```sql
CREATE TABLE player_last_login_kv
(
    player_id UInt64,
    data String  -- JSON 또는 직렬화된 데이터
)
ENGINE = EmbeddedRocksDB
PRIMARY KEY player_id;
```

**장점**:
- ✅ 실시간 쓰기 가능
- ✅ Key-Value에 최적화
- ✅ Point Query 성능 우수

**단점**:
- ❌ 복잡한 쿼리 불가
- ❌ 데이터를 JSON 등으로 직렬화 필요
- ❌ 분석 쿼리 불가능

---

### Level 5: MySQL Protocol 최적화

#### 5.1 Native Protocol 사용

**현재**: MySQL Protocol (Port 9004)
**권장**: ClickHouse Native Protocol (Port 9000)

**Python 드라이버 변경**:
```python
# 현재: mysql-connector-python
import mysql.connector
conn = mysql.connector.connect(host='localhost', port=9004, ...)

# 변경: clickhouse-driver (Native Protocol)
from clickhouse_driver import Client
client = Client(host='localhost', port=9000)
result = client.execute('SELECT * FROM player_last_login WHERE player_id = 12345')
```

**효과**:
- MySQL Protocol 변환 오버헤드 제거
- 약 10-20% 성능 향상 예상
- Connection pool 관리 개선

---

#### 5.2 Connection Pool 최적화

**권장 설정**:
```python
from clickhouse_driver import Client
from clickhouse_pool import ChPool

pool = ChPool(
    host='localhost',
    port=9000,
    connections_min=8,
    connections_max=32,
    executor='thread'
)
```

**참조**: [clickhouse-pool documentation](https://clickhouse-pool.readthedocs.io/en/latest/introduction.html)

---

## 🔬 단계별 적용 및 테스트 계획

### Phase 1: 낮은 위험 최적화 (즉시 적용 가능)

1. **Uncompressed Cache 활성화**
   ```bash
   # config.xml 수정 후
   docker-compose restart clickhouse
   ```

2. **PREWHERE 쿼리 변경**
   ```python
   # benchmark.py 수정
   query = f"SELECT ... FROM player_last_login PREWHERE player_id = {player_id}"
   ```

3. **벤치마크 재실행**
   ```bash
   python3 benchmark.py
   ```

**예상 결과**: QPS 2,690 → 3,500 (약 30% 향상)

---

### Phase 2: 중간 위험 최적화 (테스트 필요)

1. **Index Granularity 변경**
   ```sql
   -- 새 테이블 생성
   CREATE TABLE player_last_login_optimized
   ENGINE = MergeTree()
   ORDER BY player_id
   SETTINGS index_granularity = 256;

   -- 데이터 복사
   INSERT INTO player_last_login_optimized SELECT * FROM player_last_login;
   ```

2. **성능 비교 테스트**

**예상 결과**: QPS 3,500 → 5,000 (약 40% 추가 향상)

---

### Phase 3: 고급 최적화 (아키텍처 변경)

1. **Dictionary 엔진 구현**
   - 쓰기는 MergeTree
   - 읽기는 Dictionary

2. **하이브리드 아키텍처**
   - 실시간 쿼리: Dictionary (Point Query)
   - 분석 쿼리: MergeTree (Aggregation)

**예상 결과**: QPS 5,000 → 10,000 (2배 추가 향상)

---

## 📊 예상 최종 성능

| 최적화 단계 | 예상 QPS | MySQL 대비 | 누적 향상률 |
|-------------|----------|------------|-------------|
| 현재 (Baseline) | 2,690 | 0.54x | - |
| Phase 1 (Cache) | 3,500 | 0.71x | +30% |
| Phase 2 (Granularity) | 5,000 | 1.01x | +86% |
| Phase 3 (Dictionary) | 10,000 | 2.03x | +272% |

**최종 목표**: ClickHouse가 MySQL을 **2배 이상 초과**하는 성능 달성

---

## 🎯 구체적인 구현 파일

### 1. 최적화된 ClickHouse 스키마

**파일**: `init/clickhouse/init_optimized.sql`

```sql
-- ============================================================
-- Phase 2: Index Granularity 최적화
-- ============================================================

CREATE DATABASE IF NOT EXISTS gamedb;

CREATE TABLE gamedb.player_last_login_v2
(
    player_id UInt64,
    player_name String,
    character_id UInt64,
    character_name String,
    character_level UInt16,
    character_class LowCardinality(String),
    server_id UInt8,
    server_name LowCardinality(String),
    last_login_at DateTime64(3),
    last_logout_at Nullable(DateTime64(3)),
    last_ip IPv4,
    last_device_type LowCardinality(String),
    last_app_version LowCardinality(String),
    total_playtime_minutes UInt32,
    vip_level UInt8,
    guild_id Nullable(UInt64),
    guild_name Nullable(String),
    last_map_id UInt16,
    last_position_x Float32,
    last_position_y Float32,
    last_position_z Float32,
    currency_gold UInt64,
    currency_diamond UInt32,
    inventory_slots_used UInt16,
    created_at DateTime64(3) DEFAULT now64(3),
    updated_at DateTime64(3) DEFAULT now64(3),

    -- Bloom Filter Index
    INDEX idx_player_id_bloom player_id TYPE bloom_filter(0.01) GRANULARITY 1
)
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS
    -- Key-value 조회 최적화
    index_granularity = 256,  -- 8192 → 256
    index_granularity_bytes = 0,  -- Adaptive 비활성화
    -- 압축 설정 (선택사항)
    min_compress_block_size = 65536,
    max_compress_block_size = 1048576;

-- 기존 데이터 복사
INSERT INTO gamedb.player_last_login_v2 SELECT * FROM gamedb.player_last_login;

-- 최적화
OPTIMIZE TABLE gamedb.player_last_login_v2 FINAL;
```

---

### 2. 캐시 최적화 설정

**파일**: `init/clickhouse/config_optimized.xml`

```xml
<?xml version="1.0"?>
<clickhouse>
    <logger>
        <level>information</level>
    </logger>

    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>

    <!-- MySQL Protocol -->
    <mysql_port>9004</mysql_port>

    <!-- ===== 캐시 최적화 ===== -->

    <!-- Mark Cache: 5GB -->
    <mark_cache_size>5368709120</mark_cache_size>

    <!-- Uncompressed Cache: 5GB -->
    <uncompressed_cache_size>5368709120</uncompressed_cache_size>

    <!-- Primary Index Cache: 2GB -->
    <index_mark_cache_size>2147483648</index_mark_cache_size>

    <!-- Query Cache: 1GB -->
    <query_cache_size>1073741824</query_cache_size>

    <!-- ===== 성능 튜닝 ===== -->

    <!-- 최대 메모리 사용량: 10GB -->
    <max_server_memory_usage>10737418240</max_server_memory_usage>

    <!-- Thread Pool -->
    <max_thread_pool_size>32</max_thread_pool_size>
    <max_thread_pool_free_size>16</max_thread_pool_free_size>

    <!-- ===== 프로파일 설정 ===== -->

    <profiles>
        <default>
            <!-- Uncompressed Cache 활성화 -->
            <use_uncompressed_cache>1</use_uncompressed_cache>

            <!-- Query Cache 활성화 -->
            <use_query_cache>1</use_query_cache>

            <!-- Cache 임계값 -->
            <merge_tree_max_rows_to_use_cache>1000000</merge_tree_max_rows_to_use_cache>
            <merge_tree_max_bytes_to_use_cache>10485760</merge_tree_max_bytes_to_use_cache>

            <!-- PREWHERE 최적화 자동 활성화 -->
            <optimize_move_to_prewhere>1</optimize_move_to_prewhere>

            <!-- 기타 최적화 -->
            <max_threads>16</max_threads>
            <max_memory_usage>8589934592</max_memory_usage>
        </default>
    </profiles>

    <users>
        <testuser>
            <password>testpass</password>
            <profile>default</profile>
            <networks>
                <ip>::/0</ip>
            </networks>
            <quota>default</quota>
        </testuser>
    </users>
</clickhouse>
```

---

### 3. Dictionary 엔진 구현

**파일**: `init/clickhouse/create_dictionary.sql`

```sql
-- ============================================================
-- Phase 3: Dictionary 엔진으로 Point Query 최적화
-- ============================================================

-- 1. Source 테이블 (이미 존재하는 player_last_login_v2 사용)

-- 2. Dictionary 생성
CREATE DICTIONARY gamedb.player_last_login_dict
(
    player_id UInt64,
    player_name String,
    character_id UInt64,
    character_name String,
    character_level UInt16,
    character_class String,
    server_id UInt8,
    server_name String,
    last_login_at DateTime64(3),
    currency_gold UInt64,
    currency_diamond UInt32
)
PRIMARY KEY player_id
SOURCE(CLICKHOUSE(
    HOST 'localhost'
    PORT 9000
    USER 'testuser'
    PASSWORD 'testpass'
    DB 'gamedb'
    TABLE 'player_last_login_v2'
))
LIFETIME(MIN 60 MAX 300)  -- 1-5분 주기로 갱신
LAYOUT(HASHED())  -- 메모리 내 해시테이블
SETTINGS(format_csv_allow_single_quotes = 0);

-- 3. 쿼리 예제
SELECT
    dictGet('gamedb.player_last_login_dict', 'player_name', toUInt64(12345)) AS player_name,
    dictGet('gamedb.player_last_login_dict', 'character_name', toUInt64(12345)) AS character_name,
    dictGet('gamedb.player_last_login_dict', 'last_login_at', toUInt64(12345)) AS last_login_at,
    dictGet('gamedb.player_last_login_dict', 'currency_gold', toUInt64(12345)) AS currency_gold;

-- 4. Dictionary 상태 확인
SELECT * FROM system.dictionaries WHERE name = 'player_last_login_dict';
```

---

### 4. 최적화된 벤치마크 스크립트

**파일**: `benchmark_optimized.py`

```python
#!/usr/bin/env python3
"""
Optimized ClickHouse Benchmark
- Native protocol support
- PREWHERE optimization
- Dictionary support
"""

from clickhouse_driver import Client
import time
import random
import statistics
import concurrent.futures
from dataclasses import dataclass, field
from typing import List
import json
from datetime import datetime
import threading

@dataclass
class BenchmarkResult:
    target: str
    concurrency: int
    total_queries: int
    duration_seconds: float
    successful_queries: int
    failed_queries: int
    latencies_ms: List[float] = field(default_factory=list)

    @property
    def qps(self) -> float:
        return self.successful_queries / self.duration_seconds if self.duration_seconds > 0 else 0

    @property
    def avg_latency_ms(self) -> float:
        return statistics.mean(self.latencies_ms) if self.latencies_ms else 0

    @property
    def p50_latency_ms(self) -> float:
        return statistics.median(self.latencies_ms) if self.latencies_ms else 0

    @property
    def p95_latency_ms(self) -> float:
        if not self.latencies_ms:
            return 0
        sorted_lat = sorted(self.latencies_ms)
        return sorted_lat[int(len(sorted_lat) * 0.95)]

    @property
    def p99_latency_ms(self) -> float:
        if not self.latencies_ms:
            return 0
        sorted_lat = sorted(self.latencies_ms)
        return sorted_lat[int(len(sorted_lat) * 0.99)]


class ClickHouseOptimizedBenchmark:
    MAX_PLAYER_ID = 2_000_000
    QUERIES_PER_WORKER = 500

    def __init__(self, use_native=True, use_prewhere=True, use_dictionary=False):
        self.use_native = use_native
        self.use_prewhere = use_prewhere
        self.use_dictionary = use_dictionary
        self.results: List[BenchmarkResult] = []

    def create_client(self):
        """Create ClickHouse client using native protocol"""
        return Client(host='localhost', port=9000,
                     user='testuser', password='testpass',
                     database='gamedb')

    def execute_mergetree_query(self, client, player_id: int) -> tuple:
        """Standard MergeTree query"""
        where_clause = "PREWHERE" if self.use_prewhere else "WHERE"
        query = f"""
            SELECT player_id, player_name, character_id, character_name,
                   character_level, character_class, server_id, server_name,
                   last_login_at, currency_gold, currency_diamond
            FROM player_last_login_v2
            {where_clause} player_id = {player_id}
        """

        try:
            start_time = time.perf_counter()
            result = client.execute(query)
            end_time = time.perf_counter()

            latency_ms = (end_time - start_time) * 1000
            return (True, latency_ms, len(result))
        except Exception as e:
            return (False, 0, str(e))

    def execute_dictionary_query(self, client, player_id: int) -> tuple:
        """Dictionary-based query"""
        query = f"""
            SELECT
                dictGet('gamedb.player_last_login_dict', 'player_name', toUInt64({player_id})) AS player_name,
                dictGet('gamedb.player_last_login_dict', 'character_name', toUInt64({player_id})) AS character_name,
                dictGet('gamedb.player_last_login_dict', 'last_login_at', toUInt64({player_id})) AS last_login_at,
                dictGet('gamedb.player_last_login_dict', 'currency_gold', toUInt64({player_id})) AS currency_gold
        """

        try:
            start_time = time.perf_counter()
            result = client.execute(query)
            end_time = time.perf_counter()

            latency_ms = (end_time - start_time) * 1000
            return (True, latency_ms, len(result))
        except Exception as e:
            return (False, 0, str(e))

    def worker_thread(self, player_ids: List[int], results_list: list, lock: threading.Lock):
        client = self.create_client()
        local_latencies = []
        local_success = 0
        local_fail = 0

        for pid in player_ids:
            if self.use_dictionary:
                success, latency, _ = self.execute_dictionary_query(client, pid)
            else:
                success, latency, _ = self.execute_mergetree_query(client, pid)

            if success:
                local_latencies.append(latency)
                local_success += 1
            else:
                local_fail += 1

        client.disconnect()

        with lock:
            results_list.extend(local_latencies)
            results_list.append(('stats', local_success, local_fail))

    def run_benchmark(self, target: str, concurrency: int) -> BenchmarkResult:
        print(f"\n{'='*60}")
        print(f"Running: {target} | Concurrency: {concurrency}")
        print(f"Config: Native={self.use_native}, PREWHERE={self.use_prewhere}, Dict={self.use_dictionary}")
        print(f"{'='*60}")

        total_queries = concurrency * self.QUERIES_PER_WORKER
        all_player_ids = [random.randint(1, self.MAX_PLAYER_ID) for _ in range(total_queries)]

        chunks = [
            all_player_ids[i:i + self.QUERIES_PER_WORKER]
            for i in range(0, total_queries, self.QUERIES_PER_WORKER)
        ]

        results_list = []
        lock = threading.Lock()

        # Warmup
        print("Warming up...")
        client = self.create_client()
        for pid in [random.randint(1, self.MAX_PLAYER_ID) for _ in range(10)]:
            if self.use_dictionary:
                self.execute_dictionary_query(client, pid)
            else:
                self.execute_mergetree_query(client, pid)
        client.disconnect()

        print(f"Executing {total_queries} queries...")
        start_time = time.perf_counter()

        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
            futures = [
                executor.submit(self.worker_thread, chunk, results_list, lock)
                for chunk in chunks
            ]
            concurrent.futures.wait(futures)

        end_time = time.perf_counter()
        duration = end_time - start_time

        latencies = [r for r in results_list if not isinstance(r, tuple)]
        stats = [r for r in results_list if isinstance(r, tuple) and r[0] == 'stats']

        total_success = sum(s[1] for s in stats)
        total_fail = sum(s[2] for s in stats)

        result = BenchmarkResult(
            target=target,
            concurrency=concurrency,
            total_queries=total_queries,
            duration_seconds=duration,
            successful_queries=total_success,
            failed_queries=total_fail,
            latencies_ms=latencies
        )

        self.print_result(result)
        return result

    def print_result(self, r: BenchmarkResult):
        print(f"\n--- Results ---")
        print(f"Queries: {r.successful_queries:,} / {r.total_queries:,}")
        print(f"Duration: {r.duration_seconds:.2f}s")
        print(f"QPS: {r.qps:,.2f}")
        print(f"Latency: avg={r.avg_latency_ms:.2f}ms, p50={r.p50_latency_ms:.2f}ms, p95={r.p95_latency_ms:.2f}ms, p99={r.p99_latency_ms:.2f}ms")


def main():
    print("ClickHouse Optimized Benchmark")
    print("=" * 50)

    concurrency_levels = [8, 16, 24, 32]

    # Phase 1: Baseline (현재)
    print("\n### BASELINE: Current Settings")
    baseline = ClickHouseOptimizedBenchmark(use_native=False, use_prewhere=False, use_dictionary=False)
    baseline_results = [baseline.run_benchmark("ClickHouse-Baseline", c) for c in concurrency_levels]

    # Phase 2: Native + PREWHERE
    print("\n### PHASE 1: Native Protocol + PREWHERE")
    phase1 = ClickHouseOptimizedBenchmark(use_native=True, use_prewhere=True, use_dictionary=False)
    phase1_results = [phase1.run_benchmark("ClickHouse-Phase1", c) for c in concurrency_levels]

    # Phase 3: Dictionary (옵션 - Dictionary가 생성되어 있을 때만)
    try:
        print("\n### PHASE 3: Dictionary Engine")
        phase3 = ClickHouseOptimizedBenchmark(use_native=True, use_prewhere=True, use_dictionary=True)
        phase3_results = [phase3.run_benchmark("ClickHouse-Dictionary", c) for c in concurrency_levels]
    except Exception as e:
        print(f"Dictionary not available: {e}")
        phase3_results = []

    # 결과 비교
    print("\n" + "="*80)
    print("PERFORMANCE COMPARISON")
    print("="*80)

    for i, conc in enumerate(concurrency_levels):
        print(f"\nConcurrency {conc}:")
        print(f"  Baseline:  {baseline_results[i].qps:,.2f} QPS")
        print(f"  Phase 1:   {phase1_results[i].qps:,.2f} QPS ({phase1_results[i].qps/baseline_results[i].qps:.2f}x)")
        if phase3_results:
            print(f"  Phase 3:   {phase3_results[i].qps:,.2f} QPS ({phase3_results[i].qps/baseline_results[i].qps:.2f}x)")


if __name__ == "__main__":
    main()
```

---

## 📚 참고 자료

### ClickHouse 공식 문서
- [Query Performance Optimization Guide](https://clickhouse.com/docs/optimize/query-optimization)
- [MergeTree Settings](https://clickhouse.com/docs/operations/settings/merge-tree-settings)
- [PREWHERE Optimization](https://clickhouse.com/docs/optimize/prewhere)
- [Cache Types Documentation](https://clickhouse.com/docs/operations/caches)
- [Dictionary Documentation](https://clickhouse.com/docs/dictionary)

### 성능 최적화 가이드
- [The definitive guide to ClickHouse query optimization (2026)](https://clickhouse.com/resources/engineering/clickhouse-query-optimisation-definitive-guide)
- [ClickHouse Query Performance Optimization: 2025 Complete Guide](https://www.e6data.com/query-and-cost-optimization-hub/how-to-optimize-clickhouse-query-performance)
- [A simple guide to ClickHouse query optimization: part 1](https://clickhouse.com/blog/a-simple-guide-to-clickhouse-query-optimization-part-1)

### Key-Value 및 Point Query 최적화
- [ClickHouse® In the Storm. Part 2: Maximum QPS for key-value lookups](https://altinity.com/blog/clickhouse-in-the-storm-part-2)
- [Optimizing Clickhouse for access by ID](https://medium.com/datadenys/optimizing-clickhouse-for-access-by-id-cc415faa83c0)
- [Improving Clickhouse query performance by tuning key order](https://medium.com/datadenys/improving-clickhouse-query-performance-tuning-key-order-f406db7cfeb9)

### 인덱스 및 Bloom Filter
- [ClickHouse® Black Magic, Part 2: Bloom Filters](https://altinity.com/blog/skipping-indices-part-2-bloom-filters)
- [Use data skipping indices where appropriate](https://clickhouse.com/docs/best-practices/use-data-skipping-indices-where-appropriate)
- [Tuning Index Granularity in ClickHouse](https://chistadata.com/clickhouse-performance-index-granularity/)

### 캐시 최적화
- [Caching in ClickHouse® - The Definitive Guide Part 1](https://altinity.com/blog/caching-in-clickhouse-the-definitive-guide-part-1)
- [Boost ClickHouse performance with mark cache: A complete guide](https://www.instaclustr.com/blog/boost-clickhouse-performance-with-mark-cache-a-complete-guide/)

### Dictionary 엔진
- [Using Dictionaries to Accelerate Queries](https://clickhouse.com/blog/faster-queries-dictionaries-clickhouse)
- [Simplifying Queries with ClickHouse Dictionaries](https://aggregations.io/blog/clickhouse-dictionaries)

### 연결 및 프로토콜
- [clickhouse-pool documentation](https://clickhouse-pool.readthedocs.io/en/latest/introduction.html)
- [ClickHouse and MySQL - Better Together](https://www.percona.com/blog/clickhouse-and-mysql-better-together/)

---

**작성일**: 2025-12-25
**기반 벤치마크**: MySQL vs ClickHouse Point Query Performance Test
**버전**: ClickHouse 25.10

이 가이드를 단계적으로 적용하면 ClickHouse Point Query 성능을 MySQL 수준 이상으로 끌어올릴 수 있습니다.
