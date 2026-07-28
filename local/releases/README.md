# ClickHouse Release Labs

[English](#english) | [한국어](#한국어)

---

## English

One directory per ClickHouse release, each a self-contained hands-on lab for that version's new features. Every lab installs its own server version, generates its own test data, and can be run independently.

### 🗂 Available Releases

| Version | Released | Labs | Features Covered |
|---------|----------|------|------------------|
| [26.7](26.7/) | 2026-07-22 | 3 | `EXPLAIN ANALYZE`, `AT TIME ZONE` / `AT LOCAL`, `groupFormat` + `-Tuple` combinator |
| [26.6](26.6/) | 2026-06-25 | 3 | Hypothetical indexes + `EXPLAIN WHATIF`, `ADD ENUM VALUES`, SQL compatibility (`SOME`/`ALL`, `* LIKE`, `ESCAPE`, `date_part`) |
| [26.5](26.5/) | 2026-05-21 | 3 | `filesystem()` table function, bare function names + `isPrime`, `tokenizeQuery` / `highlightQuery` |
| [26.4](26.4/) | 2026-04-30 | 3 | `NATURAL JOIN` on `VALUES`, array functions, string/text functions |
| [26.3](26.3/) | 2026-03-26 | 3 | Materialized CTE, natural sort key, Unicode functions |
| [26.2](26.2/) | 2026-02-26 | 3 | `primes()` function, XXH3-128 hash, `system.tokenizers` |
| [26.1](26.1/) | 2026-01-29 | 3 | `reverseBySeparator`, text index for arrays, Keeper HTTP API |
| [25.12](25.12/) | 2025-12-18 | 3 | HMAC function, Naive Bayes classifier, JOIN order optimization (DPSize) |
| [25.11](25.11/) | 2025-11-27 | 4 | `HAVING` without `GROUP BY`, fractional `LIMIT`, Map aggregation, geometry functions |
| [25.10](25.10/) | 2025-10-30 | 5 | `QBit` vector search, negative `LIMIT`/`OFFSET`, JOIN improvements, `LIMIT BY ALL`, auto statistics |
| [25.9](25.9/) | 2025-09-25 | 4 | Global join reordering, text index, streaming secondary indices, `arrayExcept` |
| [25.8](25.8/) | 2025-08-28 | 6 | New Parquet reader, hive partitioning, temp data on S3, `UNION ALL` `_table`, data lake features, MinIO |
| [25.7](25.7/) | 2025-07-24 | 4 | SQL `UPDATE`/`DELETE`, `count()` optimization, JOIN performance, bulk `UPDATE` |
| [25.6](25.6/) | 2025-06-26 | 5 | `CoalescingMergeTree`, `Time`/`Time64` types, Bech32 encoding, `lag`/`lead`, consistent snapshot |
| [25.5](25.5/) | 2025-05-22 | 5 | Vector similarity index, Hive Metastore catalog, implicit table, new functions, geo types in Parquet |

### 🚀 Running a Lab

```bash
cd local/releases/26.7      # pick a version
./00-setup.sh               # install + start that ClickHouse version
./01-explain-analyze.sh     # run the labs in order
./02-at-time-zone.sh
./03-groupformat-tuple.sh
```

### 🧱 How a Lab Is Built

Every version directory follows the same layout:

| File | Role |
|------|------|
| `README.md` | Bilingual guide: overview, per-feature detail, learning points, use cases, full release feature list |
| `00-setup.sh` | Delegates to [`../../oss-mac-setup`](../oss-mac-setup/): `set.sh <version>` then `start.sh`, then verifies the running version |
| `NN-<feature>.sh` | Thin runner — pipes the matching `.sql` into `docker exec -i clickhouse-<version> clickhouse-client --multiline --multiquery` |
| `NN-<feature>.sql` | The lab itself: numbered sections with `SELECT '===== N. Title ====='` banners, self-generated test data, cleanup left commented for inspection |

### ⚠️ One Version at a Time

`oss-mac-setup/set.sh` maps the container to **8123/9000** when a single version is configured, so only one release runs at a time. Switching versions means re-running that version's `00-setup.sh`. Container names follow the version with dots replaced by hyphens — `26.7` → `clickhouse-26-7`.

### 🔧 Connection Info

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

### 🔍 Additional Resources

- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)
- **Release Blogs**: [clickhouse.com/blog](https://clickhouse.com/blog)
- **Release Presentations**: [presentations.clickhouse.com](https://presentations.clickhouse.com/)

---

## 한국어

ClickHouse 릴리스별로 하나의 디렉토리를 두고, 각 버전의 신기능을 직접 실행해 보는 독립 실습 랩을 제공합니다. 각 랩은 자체적으로 해당 서버 버전을 설치하고 테스트 데이터를 생성하므로 독립적으로 실행할 수 있습니다.

### 🗂 제공 릴리스

| 버전 | 출시일 | 랩 수 | 다루는 기능 |
|------|--------|-------|-------------|
| [26.7](26.7/) | 2026-07-22 | 3 | `EXPLAIN ANALYZE`, `AT TIME ZONE` / `AT LOCAL`, `groupFormat` + `-Tuple` 조합자 |
| [26.6](26.6/) | 2026-06-25 | 3 | 가상 인덱스 + `EXPLAIN WHATIF`, `ADD ENUM VALUES`, SQL 호환성 (`SOME`/`ALL`, `* LIKE`, `ESCAPE`, `date_part`) |
| [26.5](26.5/) | 2026-05-21 | 3 | `filesystem()` 테이블 함수, 베어 함수 이름 + `isPrime`, `tokenizeQuery` / `highlightQuery` |
| [26.4](26.4/) | 2026-04-30 | 3 | `VALUES`에 대한 `NATURAL JOIN`, 배열 함수, 문자열/텍스트 함수 |
| [26.3](26.3/) | 2026-03-26 | 3 | 구체화 CTE, 자연 정렬 키, 유니코드 함수 |
| [26.2](26.2/) | 2026-02-26 | 3 | `primes()` 함수, XXH3-128 해시, `system.tokenizers` |
| [26.1](26.1/) | 2026-01-29 | 3 | `reverseBySeparator`, 배열 텍스트 인덱스, Keeper HTTP API |
| [25.12](25.12/) | 2025-12-18 | 3 | HMAC 함수, 나이브 베이즈 분류기, JOIN 순서 최적화 (DPSize) |
| [25.11](25.11/) | 2025-11-27 | 4 | `GROUP BY` 없는 `HAVING`, 소수 `LIMIT`, Map 집계, 기하 함수 |
| [25.10](25.10/) | 2025-10-30 | 5 | `QBit` 벡터 검색, 음수 `LIMIT`/`OFFSET`, JOIN 개선, `LIMIT BY ALL`, 자동 통계 |
| [25.9](25.9/) | 2025-09-25 | 4 | 전역 조인 재정렬, 텍스트 인덱스, 스트리밍 보조 인덱스, `arrayExcept` |
| [25.8](25.8/) | 2025-08-28 | 6 | 신규 Parquet 리더, hive 파티셔닝, S3 임시 데이터, `UNION ALL` `_table`, 데이터 레이크, MinIO |
| [25.7](25.7/) | 2025-07-24 | 4 | SQL `UPDATE`/`DELETE`, `count()` 최적화, JOIN 성능, 대량 `UPDATE` |
| [25.6](25.6/) | 2025-06-26 | 5 | `CoalescingMergeTree`, `Time`/`Time64` 타입, Bech32 인코딩, `lag`/`lead`, 일관된 스냅샷 |
| [25.5](25.5/) | 2025-05-22 | 5 | 벡터 유사도 인덱스, Hive Metastore 카탈로그, 암시적 테이블, 신규 함수, Parquet 지오 타입 |

### 🚀 랩 실행

```bash
cd local/releases/26.7      # 버전 선택
./00-setup.sh               # 해당 ClickHouse 버전 설치 및 기동
./01-explain-analyze.sh     # 순서대로 실행
./02-at-time-zone.sh
./03-groupformat-tuple.sh
```

### 🧱 랩 구성 방식

모든 버전 디렉토리는 동일한 구조를 따릅니다.

| 파일 | 역할 |
|------|------|
| `README.md` | 영/한 가이드: 개요, 기능별 상세, 학습 포인트, 활용 사례, 릴리스 전체 기능 목록 |
| `00-setup.sh` | [`../../oss-mac-setup`](../oss-mac-setup/)에 위임 — `set.sh <버전>` 후 `start.sh`, 이어서 기동된 버전 검증 |
| `NN-<기능>.sh` | 얇은 실행 스크립트 — 대응 `.sql`을 `docker exec -i clickhouse-<버전> clickhouse-client --multiline --multiquery`로 전달 |
| `NN-<기능>.sql` | 랩 본문 — `SELECT '===== N. 제목 ====='` 배너로 구분된 번호 섹션, 자체 생성 테스트 데이터, 확인을 위해 주석 처리된 정리 구문 |

### ⚠️ 한 번에 한 버전

`oss-mac-setup/set.sh`는 단일 버전이 구성된 경우 컨테이너를 **8123/9000**에 매핑하므로 한 번에 하나의 릴리스만 실행됩니다. 버전을 바꾸려면 해당 버전의 `00-setup.sh`를 다시 실행하세요. 컨테이너 이름은 버전의 점을 하이픈으로 바꾼 형태입니다 — `26.7` → `clickhouse-26-7`.

### 🔧 접속 정보

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (비밀번호 없음)

### 🔍 추가 자료

- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)
- **Release Blogs**: [clickhouse.com/blog](https://clickhouse.com/blog)
- **Release Presentations**: [presentations.clickhouse.com](https://presentations.clickhouse.com/)

---

**Happy Learning! 🚀**
