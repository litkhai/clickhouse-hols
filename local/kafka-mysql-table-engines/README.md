# Kafka-MySQL-ClickHouse Integration with MView Block Size Testing

Kafka에서 ClickHouse로 데이터를 pull하고, Materialized View를 통해 MySQL로 자동 변환하는 통합 환경입니다. MView의 `min_insert_block_size_rows`, `max_block_size` 등의 설정이 실제로 적용되는지 검증할 수 있습니다.

## 📋 목차

- [아키텍처](#아키텍처)
- [사전 요구사항](#사전-요구사항)
- [빠른 시작](#빠른-시작)
- [데이터 플로우](#데이터-플로우)
- [Block Size 설정 검증](#block-size-설정-검증)
- [스크립트 설명](#스크립트-설명)
- [문제 해결](#문제-해결)

---

## 🏗️ 아키텍처

```
Kafka Producer (Python)
    │
    ├─> Kafka Topic: test-events
    │
    ├─> ClickHouse Kafka Engine (kafka_events)
    │
    ├─> MView: kafka_to_buffer_mv
    │
    ├─> Buffer Table (events_buffer) - MergeTree
    │
    ├─> MView: buffer_to_mysql_mv (WITH SETTINGS)
    │       ├─ max_block_size = 1000
    │       ├─ min_insert_block_size_rows = 5000
    │       └─ min_insert_block_size_bytes = 268435456
    │
    └─> MySQL Table Engine (mysql_aggregated_events)
            │
            └─> MySQL Database (testdb.aggregated_events)
```

---

## 📦 사전 요구사항

- Docker & Docker Compose
- Python 3.7+
- pip (Python package manager)

---

## 🚀 빠른 시작

### 1. 환경 초기화

```bash
chmod +x *.sh
./setup.sh
```

이 명령은 다음을 수행합니다:
- 필요한 디렉토리 생성 (`mysql-init`, `clickhouse-init`, `scripts`)
- MySQL 초기화 SQL 생성
- ClickHouse 초기화 SQL 생성
- Kafka producer Python 스크립트 생성

### 2. 서비스 시작

```bash
./start.sh
```

다음 서비스들이 시작됩니다:
- Zookeeper (포트: 2181)
- Kafka (포트: 9092, 29092)
- MySQL (포트: 3306)
- ClickHouse (HTTP: 8123, Native: 9000)

### 3. Block Size 검증 테스트 실행

```bash
./test-block-size.sh
```

이 스크립트는:
1. MView 설정을 `system.tables`에서 확인
2. 기존 데이터 초기화
3. Kafka에 50,000개 이벤트 전송
4. 데이터 처리 대기 (30초)
5. ClickHouse 및 MySQL에서 결과 검증
6. `query_log`에서 실제 적용된 block size 확인

### 4. 상태 확인

```bash
./status.sh
```

현재 시스템 상태를 확인합니다:
- Docker 컨테이너 상태
- ClickHouse 테이블 목록 및 행 수
- MySQL 테이블 상태
- Kafka topic 및 consumer group 정보

### 5. 서비스 중지

```bash
./stop.sh
```

모든 Docker 컨테이너를 중지합니다.

---

## 🔄 데이터 플로우

### 1단계: Kafka → ClickHouse Kafka Engine

```sql
CREATE TABLE default.kafka_events (
    event_time DateTime DEFAULT now(),
    query_kind String,
    query_duration_ms UInt32
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'test-events',
    kafka_group_name = 'clickhouse_consumer',
    kafka_format = 'JSONEachRow';
```

### 2단계: Kafka Engine → Buffer Table (MView)

```sql
CREATE MATERIALIZED VIEW default.kafka_to_buffer_mv
TO default.events_buffer
AS
SELECT
    event_time,
    query_kind,
    query_duration_ms
FROM default.kafka_events;
```

### 3단계: Buffer → MySQL (MView with SETTINGS)

```sql
CREATE MATERIALIZED VIEW default.buffer_to_mysql_mv
TO default.mysql_aggregated_events
AS
SELECT
    toDate(event_time) AS event_date,
    query_kind,
    count() AS query_count,
    sum(query_duration_ms) AS total_duration_ms
FROM default.events_buffer
GROUP BY event_date, query_kind
SETTINGS
    max_block_size = 1000,
    min_insert_block_size_rows = 5000,
    min_insert_block_size_bytes = 268435456;
```

---

## 🔍 Block Size 설정 검증

### 설정 값 의미

| 설정 | 기본값 | 테스트 값 | 설명 |
|------|--------|-----------|------|
| `max_block_size` | 65536 | 1000 | 소스 테이블에서 읽는 블록 크기 |
| `min_insert_block_size_rows` | 1048576 | 5000 | 타겟 테이블에 쓰는 최소 행 수 |
| `min_insert_block_size_bytes` | 268435456 | 268435456 | 타겟 테이블에 쓰는 최소 바이트 수 |

### 검증 방법

#### 1. system.tables에서 설정 확인

```bash
docker exec clickhouse clickhouse-client --query "
SELECT
    name,
    create_table_query
FROM system.tables
WHERE name = 'buffer_to_mysql_mv'
FORMAT Vertical
"
```

출력 예시:
```
name:              buffer_to_mysql_mv
create_table_query: CREATE MATERIALIZED VIEW default.buffer_to_mysql_mv ...
                    SETTINGS max_block_size = 1000,
                            min_insert_block_size_rows = 5000,
                            min_insert_block_size_bytes = 268435456
```

#### 2. query_log에서 실행 시 적용 확인

```bash
docker exec clickhouse clickhouse-client --query "
SELECT
    event_time,
    query_kind,
    Settings['max_block_size'] AS max_block_size,
    Settings['min_insert_block_size_rows'] AS min_insert_block_size_rows,
    read_rows,
    written_rows
FROM system.query_log
WHERE query LIKE '%buffer_to_mysql_mv%'
    AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 5
FORMAT Vertical
"
```

#### 3. 데이터 검증

```bash
# ClickHouse에서 확인
docker exec clickhouse clickhouse-client --query "
SELECT * FROM default.mysql_aggregated_events
FORMAT PrettyCompact
"

# MySQL에서 직접 확인
docker exec mysql mysql -u clickhouse -pclickhouse testdb -e "
SELECT * FROM aggregated_events;
"
```

---

## 📜 스크립트 설명

### setup.sh
- 환경 초기화 및 필요한 파일 생성
- MySQL/ClickHouse 초기화 SQL 작성
- Kafka producer Python 스크립트 생성

### start.sh
- Docker Compose로 모든 서비스 시작
- 각 서비스의 health check 수행
- Kafka topic 생성 (test-events)

### stop.sh
- 모든 Docker 컨테이너 중지
- 데이터 볼륨은 유지 (삭제하려면 `docker-compose down -v`)

### reset-tables.sh
- ClickHouse의 모든 테이블/MView를 DROP하고 재생성
- 테스트 환경을 초기 상태로 리셋

### test-block-size.sh
- Block size 설정을 포괄적으로 검증
- Kafka producer를 통해 테스트 데이터 생성
- ClickHouse 및 MySQL에서 결과 확인

### status.sh
- 전체 시스템 상태를 한눈에 확인
- Docker 컨테이너, 테이블, 데이터 카운트, Kafka 정보 표시

### scripts/kafka_producer.py
- Kafka에 테스트 이벤트를 전송하는 Python 스크립트
- JSONEachRow 형식으로 데이터 전송
- 사전 준비: `pip3 install kafka-python`
- 사용 예시:
  ```bash
  python3 scripts/kafka_producer.py \
      --bootstrap-servers localhost:9092 \
      --topic test-events \
      --num-events 10000 \
      --batch-size 100
  ```

---

## 🔧 문제 해결

### Kafka 연결 실패

```bash
# Kafka 로그 확인
docker-compose logs kafka

# Kafka topics 확인
docker exec kafka kafka-topics --list --bootstrap-server localhost:29092
```

### MySQL 연결 실패

```bash
# MySQL 로그 확인
docker-compose logs mysql

# MySQL 연결 테스트
docker exec mysql mysql -u clickhouse -pclickhouse -e "SELECT 1;"
```

### ClickHouse에서 Kafka 소비 안 됨

```bash
# ClickHouse 로그 확인
docker-compose logs clickhouse

# Kafka consumer group 확인
docker exec kafka kafka-consumer-groups \
    --bootstrap-server localhost:29092 \
    --group clickhouse_consumer \
    --describe
```

### MView 동작 확인

```bash
# MView 존재 확인
docker exec clickhouse clickhouse-client --query "
SELECT name, engine, create_table_query
FROM system.tables
WHERE engine = 'MaterializedView'
"

# MView 재생성
./reset-tables.sh
```

### 데이터가 MySQL로 전달되지 않음

1. ClickHouse buffer에 데이터가 있는지 확인:
   ```bash
   docker exec clickhouse clickhouse-client --query "
   SELECT count() FROM default.events_buffer
   "
   ```

2. MySQL Table Engine 연결 확인:
   ```bash
   docker exec clickhouse clickhouse-client --query "
   SELECT * FROM default.mysql_aggregated_events LIMIT 10
   "
   ```

3. MySQL에서 직접 확인:
   ```bash
   docker exec mysql mysql -u clickhouse -pclickhouse testdb -e "
   SELECT * FROM aggregated_events LIMIT 10;
   "
   ```

---

## 📊 테스트 시나리오

### 시나리오 1: 소량 데이터 (1,000건)
```bash
python3 scripts/kafka_producer.py --num-events 1000
```
예상: `min_insert_block_size_rows=5000`이므로 MySQL로 즉시 전달되지 않을 수 있음

### 시나리오 2: 중량 데이터 (10,000건)
```bash
python3 scripts/kafka_producer.py --num-events 10000
```
예상: 5000건 이상 누적되면 MySQL로 batch INSERT

### 시나리오 3: 대량 데이터 (100,000건)
```bash
python3 scripts/kafka_producer.py --num-events 100000
```
예상: 여러 번의 batch INSERT가 발생하며, `query_log`에서 block size 확인 가능

---

## 🎯 기대 결과

### ✅ 성공 시나리오

1. **MView 설정 저장 확인**
   - `system.tables`의 `create_table_query`에 SETTINGS 포함

2. **Block Size 적용 확인**
   - `query_log`에서 설정한 값 확인 가능

3. **데이터 플로우 정상 동작**
   - Kafka → ClickHouse Buffer → MySQL 순차 전달
   - MySQL에서 집계된 데이터 확인 가능

### ⚠️ 주의사항

- `min_insert_block_size_rows=5000`이므로 5000건 미만 데이터는 바로 MySQL로 전달되지 않을 수 있음
- ClickHouse의 background merge 및 MySQL polling 주기에 따라 지연 발생 가능
- 실제 운영 환경에서는 네트워크 I/O를 고려하여 block size 조정 필요

---

## 📚 참고 자료

- [ClickHouse Kafka Engine](https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka)
- [ClickHouse MySQL Engine](https://clickhouse.com/docs/en/engines/table-engines/integrations/mysql)
- [ClickHouse Materialized Views](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)
- [ClickHouse Settings](https://clickhouse.com/docs/en/operations/settings/settings)

---

## 📝 라이선스

[MIT](../../LICENSE) — 저장소 전체와 동일합니다.

---

**작성일**: 2025-12-13
**테스트 환경**: Docker Desktop, ClickHouse latest, MySQL 8.0, Kafka 7.5.0
