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
./run_matrix.py                      # all six versions, about 8 minutes on a quiet machine; pulls nothing, images must exist
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
| `06-memory-cap.sql` | uncapped peaks of the default, `hash`, `partial_merge`, `grace_hash`; `grace_hash` with 8 and 16 buckets and the default with `max_bytes_before_external_join`, under `max_memory_usage = 800000000` | which paths finish far below a cap their build side exceeds (5M `customers_big` rows, about 1.7 GiB uncapped) |
| `07-lazy-replication.sql` | many-to-many with a wide column, default / on / off | `enable_lazy_columns_replication` |
| `08-syntax.sql` | `ASOF LEFT`, `LEFT SEMI`, `LEFT ANTI`, `PASTE`, `NATURAL`, `USING`, `FULL` with `join_use_nulls`, `LEFT JOIN LATERAL` | from which version each parses |
| `09-explain.sql` | `EXPLAIN actions = 1` of the runtime-filter, LATERAL and LEFT arbitrary-ON joins | plan text, stored in the JSON |
| `10-scale.sql` | 50M-row `facts_big` x 5M-row `customers_big`: big table left, big table right, star join, many-to-many wide column, the same with `enable_lazy_columns_replication = 0`; `repeat=5` | time differences above noise level (the big tables are created in `00-data.sql`, about 40 s of data load per version) |

Every probe succeeds on 26.10 (`tools/hol run` stops at the first exception). Failures on older
versions are the result, shown as `✗ Code N` (1 UNSUPPORTED_METHOD, 48 NOT_IMPLEMENTED, 62 SYNTAX_ERROR,
115 UNKNOWN_SETTING, 241 MEMORY_LIMIT_EXCEEDED, 403 INVALID_JOIN_ON_EXPRESSION).

### What changed between versions

Written only from [RESULTS.md](RESULTS.md) (run on 2026-11-04, 12 CPUs, 15.6 GiB Docker VM; other
containers were running on the machine, so absolute times are noisy and are not used below).

- **Non-equi `ON`.** On 24.8.14.39 every non-equi form fails with Code 403 unless
  `allow_experimental_join_condition = 1` is set (`03-equi-ineq-inner-flag` runs, `03-equi-ineq-inner` does not). From 25.3.14.14 the
  range, arbitrary INNER and equality-plus-inequality forms run without the flag. The LEFT join with an arbitrary expression
  (`03-arbitrary-left`) still fails with Code 403 on 25.3 through 26.8.36.3, with or without the flag, and runs only on 26.10.3.7.
- **Range joins.** On 26.8.36.3 and 26.10.3.7 `03-range-inner` uses IE join (`ie_join` is in the default `join_algorithm` list of both; it is
  not in the list of 25.3 to 26.3) and `read_rows` drops from 5,000,100 to 1,112,053.
- **Correlated subqueries.** `EXISTS` and `NOT EXISTS` fail with Code 1 on 24.8 and 25.3 and run from 25.8.33.6 (where
  `allow_experimental_correlated_subqueries` exists, default 1). The correlated scalar subquery in the select list fails with Code 48 on 25.8, 26.3 and 26.8 and runs on 26.10.
- **Runtime filters.** `enable_join_runtime_filters` exists from 26.3.62.3 (default 1). The setting does not change `read_rows`; it changes how many rows reach
  the join: `JoinProbeTableRowCount` of `05-star-on` / `05-star-off` is 274,366 / 5,500,000 on 26.8.36.3 and 26.10.3.7 and 49,760 / 524,881 on 26.3.62.3.
  The `EXPLAIN` of `09-explain-runtime-filter` on 26.10.3.7 shows `Runtime filters: RF2(customer_id, id)` on the `facts` scan.
- **Star join build side.** `05-star-default` on 26.3.62.3 builds the hash table from `facts`: `JoinBuildTableRowCount` is 5,000,001 and peak memory 215 MiB; on 26.8.36.3 and 26.10.3.7 it builds from 24,882 rows
  (4 MiB). On 25.3 and 25.8 the build side is 500,001 rows.
- **Join side and memory.** With the big table written on the right (`02-big-right-default`), 24.8.14.39 peaks at 182 MiB; 25.3.14.14 peaks at 78 MiB and
  25.8 to 26.10 at 29 to 45 MiB. `query_plan_join_swap_table = 'false'` brings back 137 to 192 MiB on 25.3 to 26.10 (the setting does not exist on 24.8: Code 115).
- **Memory cap and spilling (`06-memory-cap.sql`, `errors/01`).** The build side is the 5M-row `customers_big` with its wide comment; the cap is `max_memory_usage = 800000000` (763 MiB).
  Uncapped peaks, MiB: default 1725 to 1916 (2.3 to 2.5 times the cap), `hash` 1583 to 1802 (2.1 to 2.4 times), `grace_hash` with one bucket 1784 to 2198 (2.3 to 2.9 times), `partial_merge` 990 to 1004 (1.3 times).
  Under the cap, the default, `hash`, `partial_merge` and one-bucket `grace_hash` all fail with Code 241 on all six versions (`errors/01-memory-cap-defaults.sql`); writing out `max_bytes_ratio_before_external_join = 0.5`
  gives Code 115 before 26.8 and Code 241 on 26.8 and 26.10. These paths finish: `grace_hash` with 16 buckets (275 to 316 MiB, 36 to 41 percent of the cap) and with 8 buckets (361 to 444 MiB, 47 to 58 percent) on all six versions, and the default with
  `max_bytes_before_external_join = 200000000` (395 MiB, 52 percent of the cap) on 26.8.36.3 and 26.10.3.7 only (Code 115 before: the setting does not exist). On 26.10 the spill shows in ProfileEvents
  (`ExternalProcessingFilesTotal` 64, `JoinSpillingHashJoinSwitchedToGraceJoin` 1).
- **LATERAL forms (`errors/02`).** The comma form and `CROSS JOIN LATERAL` give Code 62 on all six; a LATERAL subquery that does not reference the left side
  and `LIMIT ... WITH TIES` inside LATERAL give Code 62 on 24.8 to 26.8 and Code 48 on 26.10.3.7.
- **Time (`10-scale.sql`, 5 runs, median (min) in seconds).** One machine (12 CPUs). Other containers were running (Langfuse stacks, a MinIO/Nessie stack, others; RESULTS.md lists them with their CPU% when each version started,
  mostly small but `nessie` used 174% and a Langfuse ClickHouse 48 to 57% at some starts), so read only large gaps.

  | probe | 24.8 | 25.3 | 25.8 | 26.3 | 26.8 | 26.10 |
  |---|---|---|---|---|---|---|
  | `10-big-left` | 0.66 (0.31) | 0.43 (0.32) | 0.60 (0.44) | 0.61 (0.38) | 0.40 (0.32) | 0.23 (0.20) |
  | `10-big-right` | 2.69 (2.48) | 0.43 (0.37) | 0.42 (0.29) | 0.31 (0.25) | 0.28 (0.21) | 0.20 (0.18) |
  | `10-star` | 0.51 (0.40) | 0.49 (0.45) | 0.35 (0.31) | 1.13 (0.63) | 0.11 (0.10) | 0.11 (0.09) |
  | `10-many-to-many-wide` | 0.64 (0.52) | 1.06 (0.88) | 0.54 (0.46) | 0.61 (0.54) | 1.28 (1.02) | 0.88 (0.73) |
  | `10-many-to-many-wide-lazy-off` | Code 115 | Code 115 | Code 115 | 0.73 (0.50) | 0.86 (0.56) | 0.90 (0.82) |

  The clear gaps: the big table on the right takes 2.5 to 2.7 s and 1882 MiB on 24.8 against at most 0.43 s and 582 MiB elsewhere; the star join on 26.3 peaks at 2802 MiB (1.13 s) and on 26.8 and 26.10 at 38 MiB (0.11 s).
  For `10-many-to-many-wide`, 24.8 peaks at 602 MiB and 25.3 to 26.10 at 1426 to 1628 MiB. Its time on 26.8 (1.28 s, min 1.02) and 26.10 (0.88 s, min 0.73) is 1.4 to 2 times that of 24.8 (0.64 s, min 0.52). Turning lazy replication off does not change this on 26.8 and 26.10 (0.86 s and 0.90 s), so lazy replication is not the cause in this data; memory is also unchanged (1375 to 1481 MiB).
- **Syntax.** `NATURAL JOIN` parses from 26.8.36.3 (Code 62 before); `LEFT JOIN LATERAL` only on 26.10.3.7 (with `allow_experimental_lateral_join = 1`).
  `ASOF`, `SEMI`, `ANTI`, `PASTE`, `USING` and `FULL` with `join_use_nulls` parse on all six.
- **Lazy replication.** `enable_lazy_columns_replication` exists from 26.3.62.3 (default 1). Peak memory of `07-lazy-on` / `07-lazy-off`:
  324 / 322 MiB on 26.3, 61 / 112 MiB on 26.8, 63 / 196 MiB on 26.10.
- **`join_algorithm` default.** `default` on 24.8.14.39; `direct,parallel_hash,hash` on 25.3 to 26.3; `direct,parallel_hash,hash,ie_join` on 26.8 and 26.10.
  `used_join_algorithms` is logged only on 26.10.3.7; for the older builds RESULTS.md lists the join processors found in `EXPLAIN PIPELINE`, which is not an algorithm name.

Not examined: distributed or replicated joins, other table engines (`Join`, `Dictionary`), other data sizes, the
`full_sorting_merge` algorithm.

### `errors/`

`errors/NN-*.sql` follow the same probe rules but `tools/hol` does not run them (it globs only the top level): they hold results that are
failures on 26.10 itself. `run_matrix.py` runs them after the top-level files and RESULTS.md has a section for each.
`errors/01-memory-cap-defaults.sql` runs the `06` join under the same cap on the paths that do not spill (default, ratio written out, `hash`, `partial_merge`, one-bucket `grace_hash`);
`errors/02-lateral-forms.sql` has the LATERAL forms that do not parse or are not implemented.


### Verified

Verified on 24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3 and 26.10.3.7, 2026-11-04
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
./run_matrix.py                      # 여섯 버전 전부, 한가한 머신에서 약 8분. 이미지를 받지 않으므로 미리 있어야 함
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
| `06-memory-cap.sql` | 기본, `hash`, `partial_merge`, `grace_hash`의 무제한 최대치. 버킷 8개·16개 `grace_hash`와 `max_bytes_before_external_join`을 둔 기본값. 모두 `max_memory_usage = 800000000` | 빌드 쪽(500만 행 `customers_big`, 무제한 시 약 1.7 GiB)이 상한을 넘을 때 상한보다 한참 아래에서 끝나는 경로는 무엇인가 |
| `07-lazy-replication.sql` | 넓은 컬럼이 있는 다대다, 기본 / 켬 / 끔 | `enable_lazy_columns_replication` |
| `08-syntax.sql` | `ASOF LEFT`, `LEFT SEMI`, `LEFT ANTI`, `PASTE`, `NATURAL`, `USING`, `join_use_nulls`의 `FULL`, `LEFT JOIN LATERAL` | 어느 버전부터 파싱되나 |
| `09-explain.sql` | 런타임 필터, LATERAL, LEFT 임의 ON 조인의 `EXPLAIN actions = 1` | 계획 텍스트는 JSON에 저장 |
| `10-scale.sql` | 5천만 행 `facts_big` x 500만 행 `customers_big`: 큰 테이블 왼쪽, 오른쪽, 스타 조인, 넓은 컬럼 다대다, `enable_lazy_columns_replication = 0` 버전. `repeat=5` | 노이즈보다 큰 시간 차이 (큰 테이블은 `00-data.sql`에서 생성, 버전당 데이터 적재 약 40초) |

모든 프로브는 26.10에서 성공합니다(`tools/hol run`은 첫 예외에서 멈춥니다). 이전 버전의 실패가 곧 결과이며 `✗ Code N`으로
표시됩니다(1 UNSUPPORTED_METHOD, 48 NOT_IMPLEMENTED, 62 SYNTAX_ERROR, 115 UNKNOWN_SETTING, 241 MEMORY_LIMIT_EXCEEDED,
403 INVALID_JOIN_ON_EXPRESSION).

### 버전 간 변화

[RESULTS.md](RESULTS.md)만으로 작성했습니다(2026-11-04 실행, CPU 12개, Docker VM 15.6 GiB). 실행 중 다른 컨테이너가 같은 머신에서
돌고 있어 절대 시간은 흔들리므로 아래에서 쓰지 않습니다.

- **비동등 `ON`.** 24.8.14.39에서는 `allow_experimental_join_condition = 1`이 없으면 모든 비동등 형태가 Code 403으로 실패합니다
  (`03-equi-ineq-inner-flag`는 실행되고 `03-equi-ineq-inner`는 안 됩니다). 25.3.14.14부터 범위, 임의 식 INNER, 동등+부등 형태는 플래그 없이 실행됩니다.
  임의 식 LEFT JOIN(`03-arbitrary-left`)은 25.3부터 26.8.36.3까지 플래그 유무와 상관없이 Code 403이고 26.10.3.7에서만 실행됩니다.
- **범위 조인.** 26.8.36.3과 26.10.3.7에서 `03-range-inner`는 IE join을 쓰고(두 버전의 기본 `join_algorithm` 목록에 `ie_join`이 있고 25.3~26.3에는 없음),
  `read_rows`가 5,000,100에서 1,112,053으로 줄어듭니다.
- **상관 서브쿼리.** `EXISTS`, `NOT EXISTS`는 24.8과 25.3에서 Code 1로 실패하고 25.8.33.6부터 실행됩니다(`allow_experimental_correlated_subqueries`가 있고 기본값 1).
  select 목록의 상관 스칼라 서브쿼리는 25.8, 26.3, 26.8에서 Code 48이고 26.10에서 실행됩니다.
- **런타임 필터.** `enable_join_runtime_filters`는 26.3.62.3부터 있습니다(기본 1). 이 설정은 `read_rows`를 바꾸지 않고 조인에 들어오는 행 수를 바꿉니다:
  `05-star-on` / `05-star-off`의 `JoinProbeTableRowCount`는 26.8.36.3과 26.10.3.7에서 274,366 / 5,500,000, 26.3.62.3에서 49,760 / 524,881입니다.
  26.10.3.7의 `09-explain-runtime-filter` `EXPLAIN`에는 `facts` 스캔에 `Runtime filters: RF2(customer_id, id)`가 보입니다.
- **스타 조인 빌드 쪽.** 26.3.62.3의 `05-star-default`는 `facts`로 해시 테이블을 만듭니다: `JoinBuildTableRowCount` 5,000,001, 최대 메모리 215 MiB.
  26.8.36.3과 26.10.3.7은 24,882행(4 MiB)으로 만듭니다. 25.3과 25.8의 빌드 쪽은 500,001행입니다.
- **조인 쪽과 메모리.** 큰 테이블을 오른쪽에 쓰면(`02-big-right-default`) 24.8.14.39는 최대 182 MiB, 25.3.14.14는 78 MiB, 25.8~26.10은 29~45 MiB입니다.
  `query_plan_join_swap_table = 'false'`로 끄면 25.3~26.10에서 137~192 MiB로 돌아갑니다(24.8에는 설정이 없어 Code 115).
- **메모리 상한과 스필(`06-memory-cap.sql`, `errors/01`).** 빌드 쪽은 넓은 comment가 있는 500만 행 `customers_big`이고 상한은 `max_memory_usage = 800000000`(763 MiB)입니다.
  무제한 최대치(MiB): 기본 1725~1916(상한의 2.3~2.5배), `hash` 1583~1802(2.1~2.4배), 버킷 1개 `grace_hash` 1784~2198(2.3~2.9배), `partial_merge` 990~1004(1.3배).
  상한 아래에서 기본, `hash`, `partial_merge`, 버킷 1개 `grace_hash`는 여섯 버전 모두 Code 241로 실패합니다(`errors/01-memory-cap-defaults.sql`). `max_bytes_ratio_before_external_join = 0.5`를 명시하면
  26.8 이전은 Code 115, 26.8과 26.10은 Code 241입니다. 끝나는 경로: 버킷 16개 `grace_hash`(275~316 MiB, 상한의 36~41%)와 버킷 8개(361~444 MiB, 47~58%)는 여섯 버전 모두, `max_bytes_before_external_join = 200000000`을 둔
  기본값(395 MiB, 상한의 52%)은 26.8.36.3과 26.10.3.7에서만(이전은 설정이 없어 Code 115). 26.10의 ProfileEvents에 스필이 보입니다(`ExternalProcessingFilesTotal` 64, `JoinSpillingHashJoinSwitchedToGraceJoin` 1).
- **LATERAL 형태(`errors/02`).** 쉼표 형태와 `CROSS JOIN LATERAL`은 여섯 버전 모두 Code 62, 왼쪽을 참조하지 않는 LATERAL 서브쿼리와
  LATERAL 안의 `LIMIT ... WITH TIES`는 24.8~26.8에서 Code 62, 26.10.3.7에서 Code 48입니다.
- **시간(`10-scale.sql`, 5회, 중앙값(최소) 초).** 한 대의 머신(CPU 12개). 다른 컨테이너(Langfuse 스택, MinIO/Nessie 스택 등)가 돌고 있었고 RESULTS.md에 각 버전 시작 시점의 CPU%가 있습니다
  (대부분 작지만 일부 시작 시점에 `nessie` 174%, Langfuse ClickHouse 48~57%), 그래서 큰 차이만 보십시오.

  | 프로브 | 24.8 | 25.3 | 25.8 | 26.3 | 26.8 | 26.10 |
  |---|---|---|---|---|---|---|
  | `10-big-left` | 0.66 (0.31) | 0.43 (0.32) | 0.60 (0.44) | 0.61 (0.38) | 0.40 (0.32) | 0.23 (0.20) |
  | `10-big-right` | 2.69 (2.48) | 0.43 (0.37) | 0.42 (0.29) | 0.31 (0.25) | 0.28 (0.21) | 0.20 (0.18) |
  | `10-star` | 0.51 (0.40) | 0.49 (0.45) | 0.35 (0.31) | 1.13 (0.63) | 0.11 (0.10) | 0.11 (0.09) |
  | `10-many-to-many-wide` | 0.64 (0.52) | 1.06 (0.88) | 0.54 (0.46) | 0.61 (0.54) | 1.28 (1.02) | 0.88 (0.73) |
  | `10-many-to-many-wide-lazy-off` | Code 115 | Code 115 | Code 115 | 0.73 (0.50) | 0.86 (0.56) | 0.90 (0.82) |

  뚜렷한 차이: 큰 테이블을 오른쪽에 쓰면 24.8은 2.5~2.7초·1882 MiB, 나머지는 최대 0.43초·582 MiB입니다. 스타 조인은 26.3에서 2802 MiB(1.13초), 26.8과 26.10에서 38 MiB(0.11초)입니다.
  `10-many-to-many-wide`는 24.8이 602 MiB, 25.3~26.10이 1426~1628 MiB입니다. 시간은 26.8(1.28초, 최소 1.02)과 26.10(0.88초, 최소 0.73)이 24.8(0.64초, 최소 0.52)의 1.4~2배로. 지연 복제를 끄면 26.8과 26.10에서 시간이 달라지지 않으므로(0.86초, 0.90초) 이 데이터에서 지연 복제는 원인이 아니며 메모리도 같습니다(1375~1481 MiB).
- **문법.** `NATURAL JOIN`은 26.8.36.3부터 파싱됩니다(이전은 Code 62). `LEFT JOIN LATERAL`은 26.10.3.7에서만(`allow_experimental_lateral_join = 1`).
  `ASOF`, `SEMI`, `ANTI`, `PASTE`, `USING`, `join_use_nulls`의 `FULL`은 여섯 버전 모두 파싱됩니다.
- **지연 복제.** `enable_lazy_columns_replication`은 26.3.62.3부터 있습니다(기본 1). `07-lazy-on` / `07-lazy-off` 최대 메모리:
  26.3 324 / 322 MiB, 26.8 61 / 112 MiB, 26.10 63 / 196 MiB.
- **`join_algorithm` 기본값.** 24.8.14.39는 `default`, 25.3~26.3은 `direct,parallel_hash,hash`, 26.8과 26.10은 `direct,parallel_hash,hash,ie_join`.
  `used_join_algorithms`는 26.10.3.7에서만 기록됩니다. 이전 빌드는 RESULTS.md에 `EXPLAIN PIPELINE`에서 찾은 조인 프로세서를 적었으며 알고리즘 이름이 아닙니다.

다루지 않은 것: 분산·복제 조인, 다른 테이블 엔진(`Join`, `Dictionary`), 다른 데이터 크기, `full_sorting_merge` 알고리즘.

### `errors/`

`errors/NN-*.sql`은 프로브 규칙이 같지만 `tools/hol`은 최상위만 읽으므로 실행하지 않습니다. 26.10에서도 실패하는 결과를 담습니다.
`run_matrix.py`가 최상위 파일 뒤에 실행하고 RESULTS.md에 각각 절이 생깁니다. `errors/01-memory-cap-defaults.sql`은 `06`의 조인을 같은 상한에서 스필하지 않는 경로(기본, 비율 명시, `hash`, `partial_merge`, 버킷 1개 `grace_hash`)로 실행하고,
`errors/02-lateral-forms.sql`은 파싱되지 않거나 구현되지 않은 LATERAL 형태입니다.


### 검증

24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3, 26.10.3.7에서 2026-11-04에 검증
(`./run_matrix.py` 여섯 버전 전부, `tools/hol run`은 26.10.3.7).
