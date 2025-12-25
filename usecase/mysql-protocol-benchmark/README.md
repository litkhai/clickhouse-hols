# MySQL vs ClickHouse Point Query 성능 비교

게임 서버에서 플레이어 마지막 접속 정보 조회 성능 비교 테스트

## 테스트 목적

- **유즈케이스**: 앱에서 플레이어 캐릭터 마지막 접속 정보 조회
- **핵심 질문**: ClickHouse가 Point Query (Primary Key 기반 단일 row 조회)에서 충분한 성능을 제공하는가?
- **ClickHouse 최적화**: Primary Key ORDER BY + Bloom Filter Index

## 환경

- 데이터: 200만 유저
- 동시성: 8, 16, 24, 32
- 쿼리: player_id 기반 단일 row SELECT

---

## 실행 방법

### 1. 컨테이너 시작

```bash
cd usecase/mysql-protocol-benchmark
docker-compose up -d
```

### 2. ClickHouse 데이터 초기화 (1-2분)

```bash
docker exec -i clickhouse-test clickhouse-client < init/clickhouse/init.sql
```

### 3. MySQL 데이터 초기화 (10-15분)

```bash
docker exec -it mysql-test mysql -u testuser -ptestpass gamedb < init/mysql/02_generate_data.sql
```

또는 MySQL 접속 후 직접 실행:

```bash
docker exec -it mysql-test mysql -u testuser -ptestpass gamedb
mysql> source /docker-entrypoint-initdb.d/02_generate_data.sql
```

### 4. 연결 테스트

```bash
# MySQL
mysql -h localhost -P 3306 -u testuser -ptestpass gamedb -e "SELECT COUNT(*) FROM player_last_login;"

# ClickHouse (MySQL Protocol)
mysql -h localhost -P 9004 -u testuser -ptestpass gamedb -e "SELECT count() FROM player_last_login;"
```

### 5. 벤치마크 실행

```bash
pip install mysql-connector-python
python benchmark.py
```

---

## ClickHouse 최적화 포인트

### 1. Primary Key ORDER BY

```sql
ORDER BY player_id
```

- player_id 기반 Binary Search 가능
- Sparse Index로 해당 Granule 빠르게 탐색

### 2. Bloom Filter Index

```sql
INDEX idx_player_id_bloom player_id TYPE bloom_filter(0.01) GRANULARITY 1
```

- False Positive Rate 1%
- GRANULARITY 1: 각 granule마다 별도 bloom filter
- Point Query 시 불필요한 granule 스킵

---

## 디렉토리 구조

```
mysql-protocol-benchmark/
├── docker-compose.yml
├── benchmark.py
├── README.md
└── init/
    ├── clickhouse/
    │   ├── config.xml
    │   ├── users.xml
    │   └── init.sql
    └── mysql/
        ├── 01_schema.sql
        └── 02_generate_data.sql
```

---

## 정리

```bash
docker-compose down -v
```
