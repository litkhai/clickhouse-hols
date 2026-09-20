# TimeSeries Engine + PromQL — Self-managed ClickHouse

[English](#english) | [한국어](#한국어)

---

## English

A hands-on lab for ClickHouse's `TimeSeries` table engine and its PromQL query
dialect — both still experimental, both changing release to release, and
both barely documented beyond "here is the flag name". This lab was built by
actually running every statement against a real container and recording what
happened, including the parts the docs get wrong or leave out.

**Verified against ClickHouse 26.8.8 — every script in this directory runs
end to end with zero exceptions.**

### Why these two features, together

The `TimeSeries` engine gives ClickHouse a native way to store Prometheus-shaped
data (a metric name, a set of tags, and a series of timestamped samples).
PromQL is the query language that data is shaped for — plain SQL can read the
same rows, but PromQL's `rate()`, `by (...)`, and range-vector selectors are
what make "what was the error rate per host over the last hour" a one-liner
instead of a window-function exercise. Neither one is very useful to learn in
isolation.

### Feature history (so you know what to expect on other versions)

| Version | What landed |
|---|---|
| **24.8 LTS** (2024-08-30) | `TimeSeries` table engine introduced, behind `allow_experimental_time_series_table` ([PR #64183](https://github.com/ClickHouse/ClickHouse/pull/64183), merged 2024-08-08) |
| **25.6** (2025-06-26) | `timeSeries*ToGrid` SQL-native helper/aggregate functions added — a separate, later addition, not the engine itself ([PR #80590](https://github.com/ClickHouse/ClickHouse/pull/80590), merged 2025-06-05) |
| **25.8** (2025-08-28) | PromQL dialect introduced (`SET dialect = 'promql'`), basic `rate`/`delta`/`increase` ([PR #75036](https://github.com/ClickHouse/ClickHouse/pull/75036), merged 2025-08-23) |
| **25.9 → 26.8** | Ongoing work: more PromQL functions and operators, `topk`/`bottomk`, direct SQL `SELECT` on a `TimeSeries` table still **not** implemented as of 26.8 |
| **26.9+** (unreleased at time of writing) | `SELECT` support for `TimeSeries` tables, `max_over_time`/`min_over_time`, Prometheus HTTP API endpoints — still evolving; treat every detail in this README as version-specific, not a stable contract |

Both features require **ClickHouse 25.8 or later** to use together at all;
this lab targets 26.8 LTS because that is what has the richest, best-tested
feature set today, and because it is the version already used by
[`local/releases/26.8`](../../local/releases/26.8/) in this repository.

### What you will find in each file

| File | What it covers |
|---|---|
| [00-setup.sh](00-setup.sh) | Pins ClickHouse 26.8 via [`local/oss-mac-setup`](../../local/oss-mac-setup/) |
| [01-schema.sql](01-schema.sql) | `CREATE TABLE ... ENGINE = TimeSeries`; what it actually builds under the hood (4 inner tables) |
| [02-load.sql](02-load.sql) | Loads 6 synthetic series (3 hosts × 2 metrics), 240 samples each |
| [03-promql-instant.sql](03-promql-instant.sql) | Instant vectors, label matching, `by (...)` aggregation, `topk` |
| [04-promql-range.sql](04-promql-range.sql) | `rate`/`delta` semantics, operators, and range queries — the shape a dashboard graph actually needs |
| [05-management.sql](05-management.sql) | Two gotchas that will otherwise cost you a debugging session, inspecting the inner tables directly, cleanup |
| [REFERENCE.md](REFERENCE.md) | Standalone cheat sheet: settings, schema, insert format, verified PromQL syntax, gotchas — no need to run anything |

### Gotchas (the reason this lab exists)

1. **There is a second, similarly-named setting —
   `allow_experimental_time_series_aggregate_functions` — and whether you
   need it is inconsistent.** It clearly gates the SQL-native
   `timeSeries*ToGrid` aggregate function family from 25.6
   (`timeSeriesRateToGrid`, `timeSeriesResampleToGridWithStaleness`, etc.),
   which `prometheusQueryRange()` uses internally. In this lab's own testing,
   `prometheusQueryRange()` failed with `UNKNOWN_AGGREGATE_FUNCTION` without
   it on one run, then succeeded without it on a freshly restarted container
   moments later — same version, same query. Plain PromQL keyword functions
   (`rate()`, `topk()` via `SET dialect = 'promql'`) worked in every test
   regardless of this setting. Until that inconsistency is understood, set
   it defensively alongside `allow_experimental_time_series_table` — it
   never hurts, and it has been observed to matter for range queries.
2. **`SELECT * FROM <timeseries_table>` does not work**, even after you have
   created the table and inserted data (`Code: 48, NOT_IMPLEMENTED`). Read it
   back through PromQL, or through the four inner tables directly.
3. **The dialect setting is session-wide.** `SET dialect = 'promql'` turns
   *every subsequent statement* into PromQL text until you switch it back —
   including things you might expect to still be SQL, like a `SELECT '...'`
   banner between two PromQL queries (it will fail to parse as PromQL).
4. **`rate()` fails silently, not loudly**, if a window (like `[2m]`) does
   not contain at least two samples — no error, just an empty result.

### Prerequisites

- Docker (for [`local/oss-mac-setup`](../../local/oss-mac-setup/))
- Nothing else — the lab installs and pins its own ClickHouse version

### Running the lab

```bash
cd usecase/timeseries-promql-oss
./00-setup.sh
./01-schema.sh
./02-load.sh
./03-promql-instant.sh
./04-promql-range.sh
./05-management.sh   # ends by dropping the table
```

### The Cloud counterpart

See [`usecase/timeseries-promql-cloud`](../timeseries-promql-cloud/) — but
read its prerequisites first. As of this writing, the `TimeSeries` engine is
**Private Preview only on ClickHouse Cloud**: most Cloud services cannot
self-enable it, and PromQL depends on a `TimeSeries` table existing, so the
whole feature pair is currently gated behind the same private-preview
approval on Cloud.

---

## 한국어

ClickHouse의 `TimeSeries` 테이블 엔진과 그 위에서 동작하는 PromQL 쿼리 dialect를
직접 실행해보는 실습입니다. 둘 다 아직 실험적 기능이고 릴리스마다 계속 바뀌며,
공식 문서는 "이 설정을 켜세요" 수준 이상을 다루지 않는 경우가 많습니다. 이
실습은 실제 컨테이너에 모든 문장을 직접 실행해보고 그 결과 — 문서가 틀렸거나
빠뜨린 부분까지 포함해서 — 를 기록해서 만들었습니다.

**ClickHouse 26.8.8 기준 검증 완료 — 이 디렉터리의 모든 스크립트는 예외 없이
끝까지 실행됩니다.**

### 왜 두 기능을 같이 다루는가

`TimeSeries` 엔진은 ClickHouse가 Prometheus 형태의 데이터(메트릭 이름, 태그
집합, 타임스탬프가 찍힌 샘플들)를 저장하는 네이티브 방법을 제공합니다.
PromQL은 그 데이터에 맞춰 설계된 쿼리 언어입니다 — 일반 SQL로도 같은 행을 읽을
수 있지만, "지난 1시간 동안 호스트별 에러율"을 한 줄로 만드는 것은 PromQL의
`rate()`, `by (...)`, range vector 선택자입니다. 둘 중 하나만 따로 배우는 건
그다지 쓸모가 없습니다.

### 기능 도입 이력 (다른 버전에서 무엇을 기대할 수 있는지)

| 버전 | 도입 내용 |
|---|---|
| **24.8 LTS** (2024-08-30) | `TimeSeries` 테이블 엔진 도입, `allow_experimental_time_series_table` 필요 ([PR #64183](https://github.com/ClickHouse/ClickHouse/pull/64183), 2024-08-08 병합) |
| **25.6** (2025-06-26) | `timeSeries*ToGrid` SQL 네이티브 헬퍼/집계 함수 추가 — 엔진 자체와는 별개로, 나중에 추가된 기능 ([PR #80590](https://github.com/ClickHouse/ClickHouse/pull/80590), 2025-06-05 병합) |
| **25.8** (2025-08-28) | PromQL dialect 도입(`SET dialect = 'promql'`), `rate`/`delta`/`increase` 기본 지원 ([PR #75036](https://github.com/ClickHouse/ClickHouse/pull/75036), 2025-08-23 병합) |
| **25.9 → 26.8** | 지속적인 기능 추가: 더 많은 PromQL 함수/연산자, `topk`/`bottomk`. `TimeSeries` 테이블에 대한 SQL `SELECT` 직접 조회는 26.8까지도 **미지원** |
| **26.9+** (작성 시점 기준 미출시) | `TimeSeries` 테이블 SELECT 지원, `max_over_time`/`min_over_time`, Prometheus HTTP API 엔드포인트 추가 — 여전히 진화 중이므로 이 문서의 세부 사항은 안정된 계약이 아니라 특정 버전 기준임을 유의 |

두 기능을 같이 쓰려면 **ClickHouse 25.8 이상**이 최소 요구사항이며, 이 실습은
가장 기능이 풍부하고 잘 검증된 **26.8 LTS**를 기준으로 합니다 — 이 저장소의
[`local/releases/26.8`](../../local/releases/26.8/)와 동일한 버전입니다.

### 파일 구성

| 파일 | 내용 |
|---|---|
| [00-setup.sh](00-setup.sh) | [`local/oss-mac-setup`](../../local/oss-mac-setup/)로 ClickHouse 26.8 고정 설치 |
| [01-schema.sql](01-schema.sql) | `CREATE TABLE ... ENGINE = TimeSeries`; 내부적으로 실제 만들어지는 4개 테이블 |
| [02-load.sql](02-load.sql) | 합성 시계열 6개(호스트 3개 × 메트릭 2개), 각 240개 샘플 적재 |
| [03-promql-instant.sql](03-promql-instant.sql) | Instant vector, 레이블 매칭, `by (...)` 집계, `topk` |
| [04-promql-range.sql](04-promql-range.sql) | `rate`/`delta` 동작 방식, 연산자, 대시보드 그래프에 실제로 필요한 range query |
| [05-management.sql](05-management.sql) | 미리 알아두지 않으면 디버깅에 시간을 쓰게 되는 함정 2가지, 내부 테이블 직접 조회, 정리 |
| [REFERENCE.md](REFERENCE.md) | 실행 없이 바로 참고하는 요약본: 설정, 스키마, 삽입 포맷, 검증된 PromQL 문법, 함정 |

### 함정 (이 실습을 만든 이유)

1. **이름이 비슷한 설정이 하나 더 있습니다 —
   `allow_experimental_time_series_aggregate_functions` — 그런데 이게 실제로
   필요한지는 테스트할 때마다 달랐습니다.** 25.6에 추가된 SQL 네이티브
   `timeSeries*ToGrid` 집계 함수 계열(`timeSeriesRateToGrid`,
   `timeSeriesResampleToGridWithStaleness` 등)을 게이팅하는 건 분명하고,
   `prometheusQueryRange()`가 내부적으로 이 함수들을 사용합니다. 이 실습을
   만드는 과정에서 한 번은 이 설정 없이 `prometheusQueryRange()`가
   `UNKNOWN_AGGREGATE_FUNCTION` 오류로 실패했다가, 컨테이너를 새로 띄운 직후
   같은 버전·같은 쿼리로 재시도했더니 설정 없이도 성공했습니다. `SET dialect
   = 'promql'`을 통한 순수 PromQL 키워드 함수(`rate()`, `topk()`)는 이 설정과
   무관하게 모든 테스트에서 동작했습니다. 이 비일관성의 원인을 명확히 확인하기
   전까지는 `allow_experimental_time_series_table`과 함께 이 설정도 방어적으로
   켜두는 것을 권장합니다 — 켜둬서 손해볼 일은 없고, range query에서는 실제로
   영향을 준 사례가 관측됐습니다.
2. **`SELECT * FROM <timeseries_table>`은 동작하지 않습니다**, 테이블을 만들고
   데이터를 넣은 뒤에도 마찬가지입니다 (`Code: 48, NOT_IMPLEMENTED`). PromQL을
   통해서, 또는 내부 테이블 4개를 직접 조회해서 읽어야 합니다.
3. **dialect 설정은 세션 전체에 적용됩니다.** `SET dialect = 'promql'` 이후의
   *모든* 문장은 되돌리기 전까지 PromQL로 해석됩니다 — 두 PromQL 쿼리 사이에
   SQL 배너(`SELECT '...'`)를 넣는 것도 예외가 아니라, PromQL 파싱 오류가 납니다.
4. **`rate()`는 오류 없이 조용히 실패합니다.** `[2m]` 같은 윈도우 안에 샘플이
   2개 미만이면 오류 대신 빈 결과만 돌아옵니다.

### 사전 요구사항

- Docker ([`local/oss-mac-setup`](../../local/oss-mac-setup/) 실행용)
- 그 외 없음 — 실습이 자체적으로 지정된 ClickHouse 버전을 설치합니다

### 실습 실행

```bash
cd usecase/timeseries-promql-oss
./00-setup.sh
./01-schema.sh
./02-load.sh
./03-promql-instant.sh
./04-promql-range.sh
./05-management.sh   # 마지막에 테이블을 삭제합니다
```

### Cloud 버전

[`usecase/timeseries-promql-cloud`](../timeseries-promql-cloud/)를 참고하되,
사전 요구사항을 먼저 읽으세요. 현재 `TimeSeries` 엔진은 **ClickHouse Cloud에서
Private Preview 상태**입니다 — 대부분의 Cloud 서비스는 스스로 활성화할 수
없고, PromQL도 `TimeSeries` 테이블이 있어야 동작하므로 두 기능 모두 Cloud에서는
같은 private-preview 승인이 필요합니다.
