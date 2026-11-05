# JOIN across ClickHouse versions

[English](#english) | [한국어](#한국어)

---

## English

The same JOIN SQL, run on six ClickHouse builds (the LTS lines 24.8, 25.3, 25.8, 26.3, 26.8 and the
latest stable 26.10). For every probe and version the runner records: did it run (or which error
code), how long, peak memory, rows read, and which join algorithm. Nothing here is quoted from a
changelog: every cell in [RESULTS.md](RESULTS.md) comes from a run, and the raw per-probe data
(including `query_log` rows, ProfileEvents and the first result rows) is in `results/<version>.json`.

### Run it

```bash
cd workload/join-across-versions
./run_matrix.py                      # all six versions, about 4 minutes on a quiet machine (2026-11-05); pulls nothing, images must exist
./run_matrix.py --versions 26.10     # one version (prefix of a line in versions.txt)
./run_matrix.py --only 05            # one file or probe-id prefix; results merge into the JSON
./run_matrix.py --report-only        # rebuild RESULTS.md from results/*.json
tools/hol run workload/join-across-versions   # from the repository root: the SQL on 26.10 only, must not raise
```

`versions.txt` pins the exact tags, oldest first. The runner (Python 3 stdlib and the Docker CLI) starts
one container per version like `tools/hol up` does, publishes no ports, runs every `NN-*.sql` and removes
the container. It is generic: a statement preceded by `-- probe: <id> [repeat=N] [show] [events]` is a
probe, the others are setup; `-- settings: a, b` in a file lists settings to look up in `system.settings`.
A statement ends with `;` at the end of a line (no line may end in `;` inside a string literal). Each statement runs in its own
`clickhouse-client` call, so the SQL uses no bare `SET`; settings are in each statement's `SETTINGS`.

### Probes

| File | Probes | Question |
|---|---|---|
| `00-data.sql` | setup | `facts` 5M rows, `customers` 500k with a ~200 byte `comment`, `regions`, `bands`, `prices`, `contacts`; `numbers()` + `cityHash64`, no `rand()` |
| `01-hash-baseline.sql` | default / `hash` / `parallel_hash` | big table left, small right: what does `join_algorithm`'s default pick |
| `02-join-side.sql` | control, big table on the right, swap disabled | does the server put the small table on the build side by itself (`query_plan_join_swap_table`) |
| `03-non-equi-on.sql` | range, arbitrary, LEFT arbitrary, equality+inequality (INNER/LEFT), with and without `allow_experimental_join_condition` | which non-equi `ON` forms run |
| `04-correlated-subquery.sql` | `EXISTS`, `NOT EXISTS`, scalar subquery in the select list | correlated subqueries |
| `05-runtime-filter.sql` | star join and a selective build side, default / on / off | `enable_join_runtime_filters`: rows read, memory, ProfileEvents |
| `06-memory-cap.sql` | uncapped peaks of the default, `hash`, `partial_merge`, `grace_hash`; `grace_hash` with 8 and 16 buckets and the default with `max_bytes_before_external_join`, under `max_memory_usage = 800000000` | which paths finish far below a cap their build side exceeds (5M `customers_big` rows, 1.6 to 1.9 GiB uncapped) |
| `07-lazy-replication.sql` | many-to-many with a wide column, default / on / off | `enable_lazy_columns_replication` |
| `08-syntax.sql` | `ASOF LEFT`, `LEFT SEMI`, `LEFT ANTI`, `PASTE`, `NATURAL`, `USING`, `FULL` with `join_use_nulls`, `LEFT JOIN LATERAL` | from which version each parses |
| `09-explain.sql` | `EXPLAIN actions = 1` of the runtime-filter, LATERAL and LEFT arbitrary-ON joins | plan text, stored in the JSON |
| `10-scale.sql` | 50M-row `facts_big` x 5M-row `customers_big`: big table left, big table right, star join, many-to-many wide column, the same with `enable_lazy_columns_replication = 0`; `repeat=5`; two `value` probes (`10-codec-columns`, `10-codec-parts`) read back the codecs | time differences above noise level (the big tables are created in `00-data.sql` with `CODEC(LZ4)` on every column, about 40 s of data load per version) |

Every probe succeeds on 26.10 (`tools/hol run` stops at the first exception). Failures on older
versions are the result, shown as `✗ Code N` (1 UNSUPPORTED_METHOD, 48 NOT_IMPLEMENTED, 62 SYNTAX_ERROR,
115 UNKNOWN_SETTING, 241 MEMORY_LIMIT_EXCEEDED, 403 INVALID_JOIN_ON_EXPRESSION).

### What changed between versions

Written only from [RESULTS.md](RESULTS.md) (run on 2026-11-05, 12 CPUs, 15.6 GiB Docker VM; no other containers during the 24.8, 25.3 and 26.10 runs, a few idle
`cap-final-*` containers of another task during 25.8, 26.3 and 26.8, so read times only for large gaps).

- **Non-equi `ON`.** On 24.8.14.39 every non-equi form fails with Code 403 unless
  `allow_experimental_join_condition = 1` is set (`03-equi-ineq-inner-flag` runs, `03-equi-ineq-inner` does not). From 25.3.14.14 the
  range, arbitrary INNER and equality-plus-inequality forms run without the flag. The LEFT join with an arbitrary expression
  (`03-arbitrary-left`) still fails with Code 403 on 25.3 through 26.8.36.3, with or without the flag, and runs only on 26.10.3.7.
- **Range joins.** On 26.10.3.7 `03-range-inner` is logged as `IE_JOIN`; `ie_join` is in the default `join_algorithm` list of 26.8.36.3
  and 26.10.3.7 and not in that of 25.3 to 26.3. `read_rows` of the 03 probes is 1,112,053 or 5,000,100 depending on version and probe
  (25.8.33.6 reads 1,112,053 for the arbitrary INNER join, which is not an IE join), so the difference is not attributed to IE join here.
- **Correlated subqueries.** `EXISTS` and `NOT EXISTS` fail with Code 1 on 24.8 and 25.3 and run from 25.8.33.6 (where
  `allow_experimental_correlated_subqueries` exists, default 1). The correlated scalar subquery in the select list fails with Code 48 on 25.8, 26.3 and 26.8 and runs on 26.10.
- **Runtime filters.** `enable_join_runtime_filters` exists from 26.3.62.3 (default 1). The setting does not change `read_rows`; it changes how many rows reach
  the join: `JoinProbeTableRowCount` of `05-star-on` / `05-star-off` is 274,366 / 5,500,000 on 26.8.36.3 and 26.10.3.7 and 49,760 / 524,881 on 26.3.62.3.
  The `EXPLAIN` of `09-explain-runtime-filter` on 26.10.3.7 shows `Runtime filters: RF2(customer_id, id)` on the `facts` scan.
- **Star join build side.** `05-star-default` on 26.3.62.3 builds the hash table from `facts`: `JoinBuildTableRowCount` is 5,000,001 and peak memory 224 MiB; on 26.8.36.3 and 26.10.3.7 it builds from 24,882 rows
  (3 MiB). On 25.3 and 25.8 the build side is 500,001 rows.
- **Join side and memory.** With the big table written on the right (`02-big-right-default`), 24.8.14.39 peaks at 185 MiB; 25.3.14.14 peaks at 77 MiB and
  25.8 to 26.10 at 29 to 46 MiB. `query_plan_join_swap_table = 'false'` brings back 130 to 192 MiB on 25.3 to 26.10 (the setting does not exist on 24.8: Code 115).
- **Memory cap and spilling (`06-memory-cap.sql`, `errors/01`).** The build side is the 5M-row `customers_big` with its wide comment; the cap is `max_memory_usage = 800000000` (763 MiB).
  Uncapped peaks, MiB: default 1662 to 1925 (2.2 to 2.5 times the cap), `hash` 1579 to 1815 (2.1 to 2.4 times), `grace_hash` with one bucket 1788 to 2231 (2.3 to 2.9 times), `partial_merge` 987 to 1009 (1.3 times).
  Under the cap, the default, `hash`, `partial_merge` and one-bucket `grace_hash` all fail with Code 241 on all six versions (`errors/01-memory-cap-defaults.sql`); writing out `max_bytes_ratio_before_external_join = 0.5`
  gives Code 115 before 26.8 and Code 241 on 26.8 and 26.10. These paths finish: `grace_hash` with 16 buckets (277 to 305 MiB, 36 to 40 percent of the cap) and with 8 buckets (363 to 452 MiB, 48 to 59 percent) on all six versions, and the default with
  `max_bytes_before_external_join = 200000000` (406 to 422 MiB, 53 to 55 percent of the cap) on 26.8.36.3 and 26.10.3.7 only (Code 115 before: the setting does not exist). On 26.10 the spill shows in ProfileEvents
  (`ExternalProcessingFilesTotal` 64, `JoinSpillingHashJoinSwitchedToGraceJoin` 1).
- **LATERAL forms (`errors/02`).** The comma form and `CROSS JOIN LATERAL` give Code 62 on all six; a LATERAL subquery that does not reference the left side
  and `LIMIT ... WITH TIES` inside LATERAL give Code 62 on 24.8 to 26.8 and Code 48 on 26.10.3.7.
- **Time (`10-scale.sql`, 5 runs, median (min) in seconds).** One machine (12 CPUs), run on 2026-11-05. The 25.8, 26.3 and 26.8 builds ran next to idle `cap-final-*` containers of another task
  (22 to 56 percent of 1200% CPU in total at those versions' starts, listed in RESULTS.md), so read only large gaps.

  | probe | 24.8 | 25.3 | 25.8 | 26.3 | 26.8 | 26.10 |
  |---|---|---|---|---|---|---|
  | `10-big-left` | 0.30 (0.24) | 0.25 (0.22) | 0.23 (0.20) | 0.20 (0.18) | 0.15 (0.14) | 0.17 (0.11) |
  | `10-big-right` | 1.23 (1.16) | 0.22 (0.21) | 0.19 (0.17) | 0.20 (0.20) | 0.15 (0.14) | 0.11 (0.10) |
  | `10-star` | 0.33 (0.26) | 0.35 (0.30) | 0.25 (0.24) | 0.32 (0.31) | 0.05 (0.05) | 0.05 (0.05) |
  | `10-many-to-many-wide` | 0.47 (0.43) | 0.62 (0.57) | 0.34 (0.29) | 0.34 (0.31) | 0.30 (0.29) | 0.38 (0.32) |
  | `10-many-to-many-wide-lazy-off` | Code 115 | Code 115 | Code 115 | 0.34 (0.32) | 0.32 (0.28) | 0.35 (0.32) |

  The clear gaps: the big table on the right takes 1.16 to 1.23 s and 1877 MiB on 24.8 against at most 0.22 s and 583 MiB elsewhere; the star join on 26.3 peaks at 2800 MiB (0.32 s) and on 26.8 and 26.10 at 37 to 43 MiB (0.05 s).
  For `10-many-to-many-wide`, 24.8 peaks at 619 MiB and 25.3 to 26.10 at 1429 to 1670 MiB. Its time is 0.30 to 0.62 s on all six builds: 26.8 (0.30 s, min 0.29) and 26.10 (0.38 s, min 0.32) are not slower than 24.8 (0.47 s, min 0.43); only 25.3 (0.62 s, min 0.57) is above it.
  The run of 2026-11-04, with other containers running, had shown 26.8 and 26.10 at 1.4 to 2 times 24.8; that gap does not reproduce. Turning lazy replication off changes the time by 0.03 s or less on 26.3, 26.8 and 26.10; memory is 28 to 64 MiB lower (1369 to 1478 MiB against 1429 to 1520 MiB).
- **Codec pin.** From 26.9 a merged part of 100 MiB or more defaults to ZSTD(3) ([ClickHouse#108786](https://github.com/ClickHouse/ClickHouse/pull/108786)); older builds use LZ4. `00-data.sql` pins `CODEC(LZ4)` on every column of the three big tables,
  so the timings compare builds, not codecs. The two `value` probes read it back: `10-codec-columns` shows `CODEC(LZ4)` on all 10 columns on every build, and `10-codec-parts` shows part default codecs `['LZ4']` on 24.8 to 26.8 and `['LZ4','ZSTD(3)']` on 26.10
  (11 parts, the largest 654130557 bytes). So on 26.10 merged parts did get a ZSTD(3) default during the run, and the pin is what kept the columns LZ4. Builds before 26.9 store LZ4 either way.
- **Syntax.** `NATURAL JOIN` parses from 26.8.36.3 (Code 62 before); `LEFT JOIN LATERAL` only on 26.10.3.7 (with `allow_experimental_lateral_join = 1`).
  `ASOF`, `SEMI`, `ANTI`, `PASTE`, `USING` and `FULL` with `join_use_nulls` parse on all six.
- **Lazy replication.** `enable_lazy_columns_replication` exists from 26.3.62.3 (default 1). Peak memory of `07-lazy-on` / `07-lazy-off`:
  328 / 328 MiB on 26.3, 63 / 136 MiB on 26.8, 65 / 119 MiB on 26.10.
- **`join_algorithm` default.** `default` on 24.8.14.39; `direct,parallel_hash,hash` on 25.3 to 26.3; `direct,parallel_hash,hash,ie_join` on 26.8 and 26.10.
  `used_join_algorithms` is logged only on 26.10.3.7; for the older builds RESULTS.md lists the join processors found in `EXPLAIN PIPELINE`, which is not an algorithm name.

Not examined: distributed or replicated joins, other table engines (`Join`, `Dictionary`), other data sizes, the
`full_sorting_merge` algorithm.

### `errors/`

`errors/NN-*.sql` follow the same probe rules but `tools/hol` does not run them (it globs only the top level): they hold results that are
failures on 26.10 itself. `run_matrix.py` runs them after the top-level files and RESULTS.md has a section for each.
`errors/01-memory-cap-defaults.sql` runs the `06` join under the same cap on the paths that do not spill (default, ratio written out, `hash`, `partial_merge`, one-bucket `grace_hash`);
`errors/02-lateral-forms.sql` has the LATERAL forms that do not parse or are not implemented.


### Screens

Captured 2026-11-04 from ClickHouse's `/play` UI on local throwaway containers, for the notes article
`core-architecture/clickhouse-join`:

- [`images/01-left-arbitrary-on-26-8.png`](images/01-left-arbitrary-on-26-8.png) — `03-arbitrary-left` on 26.8.36.3: Code 403
- [`images/02-left-arbitrary-on-26-10.png`](images/02-left-arbitrary-on-26-10.png) — the same query on 26.10.3.7: the result row
- [`images/03-runtime-filter-explain-26-10.png`](images/03-runtime-filter-explain-26-10.png) — `EXPLAIN actions = 1` of `05-star-default` on 26.10.3.7, lines 1–25 (`Runtime filters: RF2(customer_id, id)`; the `Extremes` node comes from `/play`)
- [`images/04-used-join-algorithms-26-10.png`](images/04-used-join-algorithms-26-10.png) — `query_log.used_join_algorithms` for 11 probes on 26.10.3.7 (`03-arbitrary-left` empty)

### Verified

Verified on 24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3 and 26.10.3.7, 2026-11-05
(`./run_matrix.py`, all six; `tools/hol run` on 26.10.3.7).

---

## 한국어

같은 JOIN SQL을 ClickHouse 여섯 빌드(LTS 24.8, 25.3, 25.8, 26.3, 26.8과 최신 stable 26.10)에서 실행합니다. 프로브·버전마다
실행 여부(또는 오류 코드), 시간, 최대 메모리, 읽은 행 수, JOIN 알고리즘을 기록합니다. 변경 로그에서 가져온 값은 없습니다.
[RESULTS.md](RESULTS.md)의 모든 셀은 실행 결과이고, 프로브별 원자료(`query_log` 행, ProfileEvents, 결과 첫 행)는
`results/<version>.json`에 있습니다.

### 실행

```bash
cd workload/join-across-versions
./run_matrix.py                      # 여섯 버전 전부, 한가한 머신에서 약 4분(2026-11-05). 이미지를 받지 않으므로 미리 있어야 함
./run_matrix.py --versions 26.10     # 한 버전 (versions.txt 줄의 접두사)
./run_matrix.py --only 05            # 파일 또는 프로브 id 접두사. 결과는 JSON에 병합
./run_matrix.py --report-only        # results/*.json에서 RESULTS.md 재생성
tools/hol run workload/join-across-versions   # 저장소 루트에서: 26.10에서만 SQL 실행, 예외 없어야 함
```

`versions.txt`는 정확한 태그를 오래된 순으로 고정합니다. 러너(Python 3 표준 라이브러리와 Docker CLI)는 `tools/hol up`처럼
버전마다 컨테이너 하나를 띄우고, 포트는 열지 않으며, `NN-*.sql`을 모두 실행한 뒤 컨테이너를 지웁니다. 러너는 범용입니다:
`-- probe: <id> [repeat=N] [show] [events]`가 앞에 붙은 문장이 프로브이고 나머지는 준비 문장입니다. 파일의
`-- settings: a, b`는 `system.settings`에서 조회할 설정 목록입니다. 문장은 줄 끝의 `;`로 끝나며, 문자열 리터럴 안에서 줄이 `;`로
끝나면 안 됩니다. 문장마다 별도 `clickhouse-client` 호출이므로 SQL에는 단독 `SET`이 없고 설정은 각 문장의 `SETTINGS`에 있습니다.

### 프로브

| 파일 | 프로브 | 질문 |
|---|---|---|
| `00-data.sql` | 준비 | `facts` 500만 행, `customers` 50만 행(약 200바이트 `comment`), `regions`, `bands`, `prices`, `contacts`. `numbers()`와 `cityHash64`, `rand()` 없음 |
| `01-hash-baseline.sql` | 기본 / `hash` / `parallel_hash` | 큰 테이블 왼쪽, 작은 테이블 오른쪽: `join_algorithm` 기본값이 무엇을 고르나 |
| `02-join-side.sql` | 대조군, 큰 테이블 오른쪽, 스왑 끔 | 서버가 작은 테이블을 빌드 쪽에 알아서 두나 (`query_plan_join_swap_table`) |
| `03-non-equi-on.sql` | 범위, 임의 식, LEFT 임의 식, 동등+부등(INNER/LEFT), `allow_experimental_join_condition` 유무 | 어떤 비동등 `ON`이 실행되나 |
| `04-correlated-subquery.sql` | `EXISTS`, `NOT EXISTS`, select 목록의 스칼라 서브쿼리 | 상관 서브쿼리 |
| `05-runtime-filter.sql` | 스타 조인과 선택도 높은 빌드 쪽, 기본 / 켬 / 끔 | `enable_join_runtime_filters`: 읽은 행, 메모리, ProfileEvents |
| `06-memory-cap.sql` | 기본, `hash`, `partial_merge`, `grace_hash`의 무제한 최대치. 버킷 8개·16개 `grace_hash`와 `max_bytes_before_external_join`을 둔 기본값. 모두 `max_memory_usage = 800000000` | 빌드 쪽(500만 행 `customers_big`, 무제한 시 1.6~1.9 GiB)이 상한을 넘을 때 상한보다 한참 아래에서 끝나는 경로는 무엇인가 |
| `07-lazy-replication.sql` | 넓은 컬럼이 있는 다대다, 기본 / 켬 / 끔 | `enable_lazy_columns_replication` |
| `08-syntax.sql` | `ASOF LEFT`, `LEFT SEMI`, `LEFT ANTI`, `PASTE`, `NATURAL`, `USING`, `join_use_nulls`의 `FULL`, `LEFT JOIN LATERAL` | 어느 버전부터 파싱되나 |
| `09-explain.sql` | 런타임 필터, LATERAL, LEFT 임의 ON 조인의 `EXPLAIN actions = 1` | 계획 텍스트는 JSON에 저장 |
| `10-scale.sql` | 5천만 행 `facts_big` x 500만 행 `customers_big`: 큰 테이블 왼쪽, 오른쪽, 스타 조인, 넓은 컬럼 다대다, `enable_lazy_columns_replication = 0` 버전. `repeat=5`. `value` 프로브 둘(`10-codec-columns`, `10-codec-parts`)이 코덱을 다시 읽음 | 노이즈보다 큰 시간 차이 (큰 테이블은 `00-data.sql`에서 모든 컬럼에 `CODEC(LZ4)`를 주고 생성, 버전당 데이터 적재 약 40초) |

모든 프로브는 26.10에서 성공합니다(`tools/hol run`은 첫 예외에서 멈춥니다). 이전 버전의 실패가 곧 결과이며 `✗ Code N`으로
표시됩니다(1 UNSUPPORTED_METHOD, 48 NOT_IMPLEMENTED, 62 SYNTAX_ERROR, 115 UNKNOWN_SETTING, 241 MEMORY_LIMIT_EXCEEDED,
403 INVALID_JOIN_ON_EXPRESSION).

### 버전 간 변화

[RESULTS.md](RESULTS.md)만으로 작성했습니다(2026-11-05 실행, CPU 12개, Docker VM 15.6 GiB). 24.8, 25.3, 26.10 실행 중에는 다른 컨테이너가 없었고 25.8, 26.3, 26.8 실행 중에는
다른 작업의 유휴 `cap-final-*` 컨테이너가 떠 있었으므로 시간은 큰 차이만 보십시오.

- **비동등 `ON`.** 24.8.14.39에서는 `allow_experimental_join_condition = 1`이 없으면 모든 비동등 형태가 Code 403으로 실패합니다
  (`03-equi-ineq-inner-flag`는 실행되고 `03-equi-ineq-inner`는 안 됩니다). 25.3.14.14부터 범위, 임의 식 INNER, 동등+부등 형태는 플래그 없이 실행됩니다.
  임의 식 LEFT JOIN(`03-arbitrary-left`)은 25.3부터 26.8.36.3까지 플래그 유무와 상관없이 Code 403이고 26.10.3.7에서만 실행됩니다.
- **범위 조인.** 26.10.3.7에서 `03-range-inner`는 `IE_JOIN`으로 기록됩니다. 기본 `join_algorithm` 목록에 `ie_join`이 있는 것은 26.8.36.3과
  26.10.3.7이고 25.3~26.3에는 없습니다. 03 프로브의 `read_rows`는 버전과 프로브에 따라 1,112,053 또는 5,000,100이어서(25.8.33.6은 IE join이 아닌
  임의 식 INNER 조인에서도 1,112,053), 이 차이를 IE join 때문이라고 보지 않습니다.
- **상관 서브쿼리.** `EXISTS`, `NOT EXISTS`는 24.8과 25.3에서 Code 1로 실패하고 25.8.33.6부터 실행됩니다(`allow_experimental_correlated_subqueries`가 있고 기본값 1).
  select 목록의 상관 스칼라 서브쿼리는 25.8, 26.3, 26.8에서 Code 48이고 26.10에서 실행됩니다.
- **런타임 필터.** `enable_join_runtime_filters`는 26.3.62.3부터 있습니다(기본 1). 이 설정은 `read_rows`를 바꾸지 않고 조인에 들어오는 행 수를 바꿉니다:
  `05-star-on` / `05-star-off`의 `JoinProbeTableRowCount`는 26.8.36.3과 26.10.3.7에서 274,366 / 5,500,000, 26.3.62.3에서 49,760 / 524,881입니다.
  26.10.3.7의 `09-explain-runtime-filter` `EXPLAIN`에는 `facts` 스캔에 `Runtime filters: RF2(customer_id, id)`가 보입니다.
- **스타 조인 빌드 쪽.** 26.3.62.3의 `05-star-default`는 `facts`로 해시 테이블을 만듭니다: `JoinBuildTableRowCount` 5,000,001, 최대 메모리 224 MiB.
  26.8.36.3과 26.10.3.7은 24,882행(3 MiB)으로 만듭니다. 25.3과 25.8의 빌드 쪽은 500,001행입니다.
- **조인 쪽과 메모리.** 큰 테이블을 오른쪽에 쓰면(`02-big-right-default`) 24.8.14.39는 최대 185 MiB, 25.3.14.14는 77 MiB, 25.8~26.10은 29~46 MiB입니다.
  `query_plan_join_swap_table = 'false'`로 끄면 25.3~26.10에서 130~192 MiB로 돌아갑니다(24.8에는 설정이 없어 Code 115).
- **메모리 상한과 스필(`06-memory-cap.sql`, `errors/01`).** 빌드 쪽은 넓은 comment가 있는 500만 행 `customers_big`이고 상한은 `max_memory_usage = 800000000`(763 MiB)입니다.
  무제한 최대치(MiB): 기본 1662~1925(상한의 2.2~2.5배), `hash` 1579~1815(2.1~2.4배), 버킷 1개 `grace_hash` 1788~2231(2.3~2.9배), `partial_merge` 987~1009(1.3배).
  상한 아래에서 기본, `hash`, `partial_merge`, 버킷 1개 `grace_hash`는 여섯 버전 모두 Code 241로 실패합니다(`errors/01-memory-cap-defaults.sql`). `max_bytes_ratio_before_external_join = 0.5`를 명시하면
  26.8 이전은 Code 115, 26.8과 26.10은 Code 241입니다. 끝나는 경로: 버킷 16개 `grace_hash`(277~305 MiB, 상한의 36~40%)와 버킷 8개(363~452 MiB, 48~59%)는 여섯 버전 모두, `max_bytes_before_external_join = 200000000`을 둔
  기본값(406~422 MiB, 상한의 53~55%)은 26.8.36.3과 26.10.3.7에서만(이전은 설정이 없어 Code 115). 26.10의 ProfileEvents에 스필이 보입니다(`ExternalProcessingFilesTotal` 64, `JoinSpillingHashJoinSwitchedToGraceJoin` 1).
- **LATERAL 형태(`errors/02`).** 쉼표 형태와 `CROSS JOIN LATERAL`은 여섯 버전 모두 Code 62, 왼쪽을 참조하지 않는 LATERAL 서브쿼리와
  LATERAL 안의 `LIMIT ... WITH TIES`는 24.8~26.8에서 Code 62, 26.10.3.7에서 Code 48입니다.
- **시간(`10-scale.sql`, 5회, 중앙값(최소) 초).** 한 대의 머신(CPU 12개), 2026-11-05 실행. 25.8, 26.3, 26.8 빌드는 다른 작업의 유휴 `cap-final-*` 컨테이너와 함께 돌았고
  (해당 버전 시작 시점 CPU 합계 1200% 중 22~56%, RESULTS.md에 있음) 그래서 큰 차이만 보십시오.

  | 프로브 | 24.8 | 25.3 | 25.8 | 26.3 | 26.8 | 26.10 |
  |---|---|---|---|---|---|---|
  | `10-big-left` | 0.30 (0.24) | 0.25 (0.22) | 0.23 (0.20) | 0.20 (0.18) | 0.15 (0.14) | 0.17 (0.11) |
  | `10-big-right` | 1.23 (1.16) | 0.22 (0.21) | 0.19 (0.17) | 0.20 (0.20) | 0.15 (0.14) | 0.11 (0.10) |
  | `10-star` | 0.33 (0.26) | 0.35 (0.30) | 0.25 (0.24) | 0.32 (0.31) | 0.05 (0.05) | 0.05 (0.05) |
  | `10-many-to-many-wide` | 0.47 (0.43) | 0.62 (0.57) | 0.34 (0.29) | 0.34 (0.31) | 0.30 (0.29) | 0.38 (0.32) |
  | `10-many-to-many-wide-lazy-off` | Code 115 | Code 115 | Code 115 | 0.34 (0.32) | 0.32 (0.28) | 0.35 (0.32) |

  뚜렷한 차이: 큰 테이블을 오른쪽에 쓰면 24.8은 1.16~1.23초·1877 MiB, 나머지는 최대 0.22초·583 MiB입니다. 스타 조인은 26.3에서 2800 MiB(0.32초), 26.8과 26.10에서 37~43 MiB(0.05초)입니다.
  `10-many-to-many-wide`는 24.8이 619 MiB, 25.3~26.10이 1429~1670 MiB입니다. 시간은 여섯 빌드 모두 0.30~0.62초입니다. 26.8(0.30초, 최소 0.29)과 26.10(0.38초, 최소 0.32)은 24.8(0.47초, 최소 0.43)보다 느리지 않고, 24.8보다 위인 것은 25.3(0.62초, 최소 0.57)뿐입니다.
  다른 컨테이너가 돌던 2026-11-04 실행에서는 26.8과 26.10이 24.8의 1.4~2배로 보였지만 그 차이는 재현되지 않았습니다. 지연 복제를 끄면 시간은 26.3, 26.8, 26.10 모두 0.03초 이하로 달라지고, 메모리는 28~64 MiB 낮습니다(1369~1478 MiB 대 1429~1520 MiB).
- **코덱 고정.** 26.9부터 100 MiB 이상으로 병합된 파트는 기본 코덱이 ZSTD(3)입니다([ClickHouse#108786](https://github.com/ClickHouse/ClickHouse/pull/108786)). 이전 빌드는 LZ4입니다. `00-data.sql`은 큰 테이블 셋의 모든 컬럼에 `CODEC(LZ4)`를 주어
  시간이 코덱이 아니라 빌드를 비교하게 했습니다. `value` 프로브 둘이 결과를 다시 읽습니다: `10-codec-columns`는 모든 빌드에서 컬럼 10개 전부 `CODEC(LZ4)`이고, `10-codec-parts`의 파트 기본 코덱은 24.8~26.8이 `['LZ4']`, 26.10이 `['LZ4','ZSTD(3)']`입니다
  (파트 11개, 가장 큰 것 654130557바이트). 즉 26.10에서는 실행 중 병합된 파트가 ZSTD(3) 기본값을 받았고, 컬럼을 LZ4로 유지한 것은 이 고정입니다. 26.9 이전 빌드는 고정 여부와 상관없이 LZ4로 저장합니다.
- **문법.** `NATURAL JOIN`은 26.8.36.3부터 파싱됩니다(이전은 Code 62). `LEFT JOIN LATERAL`은 26.10.3.7에서만(`allow_experimental_lateral_join = 1`).
  `ASOF`, `SEMI`, `ANTI`, `PASTE`, `USING`, `join_use_nulls`의 `FULL`은 여섯 버전 모두 파싱됩니다.
- **지연 복제.** `enable_lazy_columns_replication`은 26.3.62.3부터 있습니다(기본 1). `07-lazy-on` / `07-lazy-off` 최대 메모리:
  26.3 328 / 328 MiB, 26.8 63 / 136 MiB, 26.10 65 / 119 MiB.
- **`join_algorithm` 기본값.** 24.8.14.39는 `default`, 25.3~26.3은 `direct,parallel_hash,hash`, 26.8과 26.10은 `direct,parallel_hash,hash,ie_join`.
  `used_join_algorithms`는 26.10.3.7에서만 기록됩니다. 이전 빌드는 RESULTS.md에 `EXPLAIN PIPELINE`에서 찾은 조인 프로세서를 적었으며 알고리즘 이름이 아닙니다.

다루지 않은 것: 분산·복제 조인, 다른 테이블 엔진(`Join`, `Dictionary`), 다른 데이터 크기, `full_sorting_merge` 알고리즘.

### `errors/`

`errors/NN-*.sql`은 프로브 규칙이 같지만 `tools/hol`은 최상위만 읽으므로 실행하지 않습니다. 26.10에서도 실패하는 결과를 담습니다.
`run_matrix.py`가 최상위 파일 뒤에 실행하고 RESULTS.md에 각각 절이 생깁니다. `errors/01-memory-cap-defaults.sql`은 `06`의 조인을 같은 상한에서 스필하지 않는 경로(기본, 비율 명시, `hash`, `partial_merge`, 버킷 1개 `grace_hash`)로 실행하고,
`errors/02-lateral-forms.sql`은 파싱되지 않거나 구현되지 않은 LATERAL 형태입니다.


### 화면

2026-11-04, 로컬 일회용 컨테이너의 ClickHouse `/play` 화면에서 노트 글 `core-architecture/clickhouse-join`용으로 찍었습니다.

- [`images/01-left-arbitrary-on-26-8.png`](images/01-left-arbitrary-on-26-8.png) — 26.8.36.3의 `03-arbitrary-left`: Code 403
- [`images/02-left-arbitrary-on-26-10.png`](images/02-left-arbitrary-on-26-10.png) — 같은 쿼리, 26.10.3.7: 결과 행
- [`images/03-runtime-filter-explain-26-10.png`](images/03-runtime-filter-explain-26-10.png) — 26.10.3.7의 `05-star-default` `EXPLAIN actions = 1` 1–25행(`Runtime filters: RF2(customer_id, id)`, `Extremes` 노드는 `/play`가 붙인 것)
- [`images/04-used-join-algorithms-26-10.png`](images/04-used-join-algorithms-26-10.png) — 26.10.3.7에서 프로브 11개의 `query_log.used_join_algorithms`(`03-arbitrary-left`만 비어 있음)

### 검증

24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3, 26.10.3.7에서 2026-11-05에 검증
(`./run_matrix.py` 여섯 버전 전부, `tools/hol run`은 26.10.3.7).
