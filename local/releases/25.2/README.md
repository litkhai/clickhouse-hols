# ClickHouse 25.2 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.2 new features. This directory focuses on verified and working features newly added in ClickHouse 25.2 (released 2025-03-07, with 12 new features, 15 performance optimizations and 72 bug fixes).

### 📋 Overview

ClickHouse 25.2 is a release about getting at data faster. Parquet files gain Bloom filters so an equality lookup can skip whole row groups. A backup no longer has to be restored before it can be read — the `Backup` database engine mounts it read-only. And two new formats interleave progress events with rows, which is what the web UI's live progress bar is built on.

### 🎯 Key Features

1. **Parquet Bloom Filters** — written by default, pushed down on read
2. **`Backup` Database Engine** — query a backup without restoring it
3. **`stringCompare`, `initialQueryStartTime` and the Progress Formats**

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/25.2
./00-setup.sh

./01-parquet-bloom-filters.sh
./02-backup-database-engine.sh
./03-functions-and-progress-formats.sh
```

### 📚 Feature Details

#### 1. Parquet Bloom Filters (01-parquet-bloom-filters)

**New Feature:** ClickHouse writes Bloom filters into the Parquet files it produces (`output_format_parquet_write_bloom_filter`, on by default), and can consult them on read to skip row groups that cannot contain a value (`input_format_parquet_bloom_filter_push_down`, off by default).

**Test Content:**
- A 1M-row source table with a unique key column
- The write-side settings and their defaults
- The same data written twice, with and without filters
- File size measured through the `_size` virtual column
- The read-side push-down setting
- A point lookup with push-down on and off
- Push-down against a file that has no filters
- Range and low-cardinality predicates, where a Bloom filter cannot help
- `bits_per_value` traded against file size
- The same answer from every variant

**Key Learning Points:**
- Writing is on by default; **push-down on read is off by default** and has to be enabled per query or per profile
- The size cost scales with distinct values, not with rows: this lab's million unique keys grow the file from 1.55 MiB to 5.55 MiB, far past the ~10% the release notes quote for typical data
- Raising `output_format_parquet_bloom_filter_bits_per_value` to 20 pushes it to 9.57 MiB — fewer false positives, bigger file
- A Bloom filter answers only "is this exact value absent?", so ranges and `GROUP BY` see no benefit
- Enabling push-down against a file without filters is harmless; the reader falls back to scanning
- Results are identical either way — this is purely an I/O optimisation

**Use Cases:**
- Point lookups against Parquet on object storage, where skipping a row group saves a network read
- Data lake tables queried by a high-cardinality key
- Deciding whether the filter overhead is worth it for a given column's cardinality

---

#### 2. `Backup` Database Engine (02-backup-database-engine)

**New Feature:** `CREATE DATABASE <name> ENGINE = Backup('<source_db>', File('<backup>'))` attaches the tables inside a backup as a read-only database, instantly, with no restore step.

**Test Content:**
- Two live tables, backed up with `BACKUP TABLE ... TO File(...)`
- The live tables then moving on: 10k more rows and a mutation
- Attaching the backup as a database and listing its tables
- Reading row counts as they were at backup time
- Live versus backup, side by side
- Joining the live table to the backup to find which rows changed
- Aggregating only the rows added since the backup
- Confirming the engine is read-only
- Dropping and re-attaching the database

**Key Learning Points:**
- A relative `File('name')` lands under the server's backup directory; absolute paths must appear in `backups.allowed_path` or the server rejects them with `BAD_ARGUMENTS`
- `BACKUP` refuses to overwrite an existing destination (`BACKUP_ALREADY_EXISTS`), so the runner clears the directory to keep the lab re-runnable
- The attached database is a normal query target: it joins against live tables, so "what changed since the backup" is one query
- Dropping the database detaches it without touching the backup files, and it can be attached again
- The engine is read-only by construction — it is for reading a snapshot, not for becoming one

**Use Cases:**
- Point-in-time comparison without provisioning a restore target
- Auditing what a table looked like before an incident
- Extracting a few rows from a backup instead of restoring all of it

---

#### 3. `stringCompare`, `initialQueryStartTime` and the Progress Formats (03-functions-and-progress-formats)

**New Features:**
- `stringCompare(a, b)` — three-way comparison returning `-1`, `0` or `1`
- `initialQueryStartTime()` / `initial_query_start_time()` — start time of the initiating query
- `JSONCompactEachRowWithProgress` and `JSONCompactStringsEachRowWithProgress` — row events interleaved with progress events

**Test Content:**
- `stringCompare` on less/greater/equal pairs
- The same result assembled by hand with `multiIf`, and the two agreeing
- Ordering and bucketing by the comparator's result
- `initialQueryStartTime()` with its type and snake_case alias
- Elapsed time computed inside a running query
- Tagging a result with both the query id and its start time
- The two progress formats in `system.formats`
- What each format actually emits, including the Strings variant
- A 5M-row scan rendered through the progress format

**Key Learning Points:**
- `stringCompare` is the comparator shape sorting and diffing want, instead of combining two boolean comparisons
- `initialQueryStartTime()` reports the *initiating* query's start time, so on a distributed query every shard agrees — that is what makes it a correlation key
- The progress formats emit `{"meta":...}`, then `{"row":[...]}` lines, then `{"progress":{...}}` with `read_rows` / `total_rows_to_read` / `elapsed_ns`
- On a small result the progress event arrives at the end; on a long scan they arrive throughout, which is the point
- The Strings variant renders every value as a string, keeping large integers exact for JSON consumers that would otherwise lose precision

**Use Cases:**
- Custom clients that want a progress bar without a second polling connection
- Correlating shards of one distributed request by start time
- Sorting or diffing logic that needs a three-way comparator

---

### 🔧 Management

#### ClickHouse Connection Info

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

#### Useful Commands

```bash
cd ../../oss-mac-setup
./status.sh
./client.sh 8123
docker logs clickhouse-25-2
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
25.2/
├── README.md                              # This document
├── 00-setup.sh                            # ClickHouse 25.2 installation script
├── 01-parquet-bloom-filters.sh            # Parquet Bloom filter runner
├── 01-parquet-bloom-filters.sql           # Parquet Bloom filter SQL
├── 02-backup-database-engine.sh           # Backup engine runner (clears the backup dir first)
├── 02-backup-database-engine.sql          # Backup engine SQL
├── 03-functions-and-progress-formats.sh   # Functions + progress formats runner
└── 03-functions-and-progress-formats.sql  # Functions + progress formats SQL
```

### 🆕 What's New in 25.2

- **Parquet Bloom filters** — written on output, pushed down on input
- **`Backup` database engine** — read-only attach of a backup
- **`stringCompare`** — three-way string comparison
- **`initialQueryStartTime`** / **`initial_query_start_time`**
- **`JSONCompactEachRowWithProgress`** and **`JSONCompactStringsEachRowWithProgress`**
- **`system.latency_buckets`** system table
- **Transitive condition inference** — `a < b AND b < 5` also implies `a < 5`
- **Delta Rust Kernel integration** (experimental) — Delta Lake via the Databricks library
- **Enhanced Web UI** — live progress bar and dynamic result table, built on the new formats
- **Faster parallel hash join** — less thread contention in the build phase

### 🔍 Additional Resources

- **Release Blog**: [ClickHouse Release 25.2](https://clickhouse.com/blog/clickhouse-release-25-02)
- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 Notes

- All features verified on ClickHouse 25.2.2.39
- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out for inspection
- `01` leaves Parquet files in `user_files`; remove with `docker exec clickhouse-25-2 rm /var/lib/clickhouse/user_files/bloom_*.parquet`
- `02` writes a backup to `/var/lib/clickhouse/backups/snapshot_v1`, which its runner clears before each run


### 📄 License

[MIT](../../../LICENSE) — free to learn from and modify.

---

**Happy Learning! 🚀**

For questions, see the main [clickhouse-hols README](../../../README.md).

---

## 한국어

ClickHouse 25.2 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2025년 3월 7일 출시된 ClickHouse 25.2에서 검증된 작동 기능에 집중합니다. 신기능 12건, 성능 최적화 15건, 버그 수정 72건을 포함합니다.

### 📋 개요

ClickHouse 25.2는 데이터에 더 빨리 닿는 것에 관한 릴리스입니다. Parquet 파일에 Bloom 필터가 실려 동등 조회가 행 그룹 전체를 건너뛸 수 있고, 백업은 복원 없이도 읽을 수 있습니다(`Backup` 데이터베이스 엔진이 읽기 전용으로 마운트). 그리고 행과 진행 이벤트를 섞어 내보내는 두 포맷이 추가됐는데, 웹 UI의 실시간 진행 표시줄이 이 위에 만들어졌습니다.

### 🎯 주요 기능

1. **Parquet Bloom 필터** — 쓰기는 기본 활성, 읽기는 푸시다운
2. **`Backup` 데이터베이스 엔진** — 복원 없이 백업 조회
3. **`stringCompare`, `initialQueryStartTime`, 진행 포맷**

### 🚀 빠른 시작

```bash
cd local/releases/25.2
./00-setup.sh

./01-parquet-bloom-filters.sh
./02-backup-database-engine.sh
./03-functions-and-progress-formats.sh
```

### 📚 기능 상세

#### 1. Parquet Bloom 필터

ClickHouse가 생성하는 Parquet 파일에 Bloom 필터를 기록하고(`output_format_parquet_write_bloom_filter`, 기본 켜짐), 읽을 때 이를 참조해 값이 있을 수 없는 행 그룹을 건너뜁니다(`input_format_parquet_bloom_filter_push_down`, 기본 꺼짐).

**테스트 내용:**
- 고유 키 컬럼을 가진 100만 행 소스 테이블
- 쓰기 측 설정과 기본값
- 같은 데이터를 필터 유/무로 두 번 기록
- `_size` 가상 컬럼으로 파일 크기 측정
- 읽기 측 푸시다운 설정
- 푸시다운 on/off 상태의 포인트 조회
- 필터가 없는 파일에 대한 푸시다운
- Bloom 필터가 돕지 못하는 범위·저카디널리티 조건
- `bits_per_value`와 파일 크기의 교환
- 모든 변형에서 동일한 결과

**핵심 학습 포인트:**
- 쓰기는 기본 켜짐이지만 **읽기 푸시다운은 기본 꺼짐**이라 쿼리나 프로파일에서 켜야 합니다
- 크기 비용은 행 수가 아니라 고유값 수에 비례합니다. 이 랩의 고유 키 100만 개는 파일을 1.55 MiB → 5.55 MiB로 키워, 릴리스 노트가 말하는 약 10%를 훨씬 넘습니다
- `output_format_parquet_bloom_filter_bits_per_value`를 20으로 올리면 9.57 MiB가 됩니다 — 오탐은 줄고 파일은 커집니다
- Bloom 필터는 "이 정확한 값이 없는가?"만 답하므로 범위 조건과 `GROUP BY`에는 이득이 없습니다
- 필터가 없는 파일에 푸시다운을 켜도 무해합니다 — 스캔으로 되돌아갑니다
- 결과는 어느 쪽이든 동일합니다. 순수한 I/O 최적화입니다

#### 2. `Backup` 데이터베이스 엔진

`CREATE DATABASE <이름> ENGINE = Backup('<원본DB>', File('<백업>'))`은 백업 안의 테이블을 복원 단계 없이 즉시 읽기 전용 데이터베이스로 붙입니다.

**테스트 내용:**
- 라이브 테이블 2개를 `BACKUP TABLE ... TO File(...)`로 백업
- 이후 라이브 테이블 변경: 1만 행 추가와 뮤테이션
- 백업을 데이터베이스로 붙이고 테이블 목록 확인
- 백업 시점의 행 수 조회
- 라이브 vs 백업 비교
- 라이브와 백업을 조인해 변경된 행 찾기
- 백업 이후 추가된 행만 집계
- 엔진이 읽기 전용임을 확인
- 데이터베이스 분리 후 재연결

**핵심 학습 포인트:**
- 상대 경로 `File('이름')`은 서버 백업 디렉토리 아래에 놓입니다. 절대 경로는 `backups.allowed_path`에 있어야 하며 아니면 `BAD_ARGUMENTS`로 거부됩니다
- `BACKUP`은 기존 대상을 덮어쓰지 않습니다(`BACKUP_ALREADY_EXISTS`). 재실행을 위해 실행 스크립트가 디렉토리를 먼저 지웁니다
- 붙인 데이터베이스는 일반 쿼리 대상이라 라이브 테이블과 조인됩니다 — "백업 이후 무엇이 바뀌었나"가 쿼리 한 번이 됩니다
- 데이터베이스를 드롭해도 백업 파일은 그대로이며 다시 붙일 수 있습니다
- 엔진은 구조상 읽기 전용입니다 — 스냅샷을 읽기 위한 것이지 스냅샷이 되기 위한 것이 아닙니다

#### 3. `stringCompare`, `initialQueryStartTime`, 진행 포맷

- `stringCompare(a, b)` — `-1`, `0`, `1`을 반환하는 3방향 비교
- `initialQueryStartTime()` / `initial_query_start_time()` — 최초 쿼리의 시작 시각
- `JSONCompactEachRowWithProgress`, `JSONCompactStringsEachRowWithProgress` — 행 이벤트와 진행 이벤트를 섞어 출력

**테스트 내용:**
- 작음/큼/같음 쌍에 대한 `stringCompare`
- `multiIf`로 손수 만든 동일 결과와의 일치 확인
- 비교 결과로 정렬하고 버킷팅
- `initialQueryStartTime()`의 타입과 snake_case 별칭
- 실행 중인 쿼리 안에서 경과 시간 계산
- 쿼리 id와 시작 시각을 결과에 함께 싣기
- `system.formats`에서 두 진행 포맷 확인
- 각 포맷의 실제 출력(Strings 변형 포함)
- 500만 행 스캔을 진행 포맷으로 출력

**핵심 학습 포인트:**
- `stringCompare`는 두 개의 불리언 비교를 조합하는 대신 정렬·비교가 원하는 comparator 형태를 바로 제공합니다
- `initialQueryStartTime()`은 *최초* 쿼리의 시작 시각을 보고하므로 분산 쿼리에서 모든 샤드가 같은 값을 갖습니다 — 그래서 상관 키로 쓸 수 있습니다
- 진행 포맷은 `{"meta":...}` → `{"row":[...]}` → `{"progress":{...}}` 순으로 내보내며, 진행 이벤트에는 `read_rows`·`total_rows_to_read`·`elapsed_ns`가 담깁니다
- 결과가 작으면 진행 이벤트가 마지막에 오고, 긴 스캔에서는 중간중간 도착합니다 — 이것이 포맷의 목적입니다
- Strings 변형은 모든 값을 문자열로 렌더링해, 정밀도를 잃을 수 있는 JSON 소비자에게도 큰 정수를 정확히 전달합니다

### 🆕 25.2의 새로운 기능

- **Parquet Bloom 필터** — 출력 시 기록, 입력 시 푸시다운
- **`Backup` 데이터베이스 엔진** — 백업의 읽기 전용 연결
- **`stringCompare`** — 3방향 문자열 비교
- **`initialQueryStartTime`** / **`initial_query_start_time`**
- **`JSONCompactEachRowWithProgress`**, **`JSONCompactStringsEachRowWithProgress`**
- **`system.latency_buckets`** 시스템 테이블
- **전이적 조건 추론** — `a < b AND b < 5`에서 `a < 5`도 도출
- **Delta Rust Kernel 통합** (실험적) — Databricks 라이브러리 기반 Delta Lake
- **웹 UI 개선** — 신규 포맷 기반 실시간 진행 표시줄과 동적 결과 테이블
- **병렬 해시 조인 속도 개선** — build 단계의 스레드 경합 감소

### 🔍 추가 자료

- **Release Blog**: [ClickHouse Release 25.2](https://clickhouse.com/blog/clickhouse-release-25-02)
- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)

### 📝 참고사항

- 모든 기능은 ClickHouse 25.2.2.39에서 검증
- 각 스크립트는 독립적으로 실행 가능
- 테스트 데이터는 각 SQL 파일 안에서 생성
- 정리(cleanup) 구문은 확인을 위해 주석 처리
- `01`은 `user_files`에 Parquet 파일을 남깁니다 — 정리: `docker exec clickhouse-25-2 rm /var/lib/clickhouse/user_files/bloom_*.parquet`
- `02`는 `/var/lib/clickhouse/backups/snapshot_v1`에 백업을 만들며, 실행 스크립트가 매번 먼저 지웁니다


### 📄 라이선스

[MIT](../../../LICENSE) — 자유롭게 학습하고 수정하세요.

---

**Happy Learning! 🚀**
