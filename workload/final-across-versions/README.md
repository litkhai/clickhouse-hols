# SELECT … FINAL across ClickHouse versions

[English](#english) | [한국어](#한국어)

---

## English

The same `SELECT … FINAL` SQL run on six builds (the LTS lines 24.8, 25.3, 25.8, 26.3, 26.8 and the latest
stable 26.10). For each probe the runner records the answer (and whether it is the correct one), the time,
the rows read and, where it matters, the bytes read. Every cell in [RESULTS.md](RESULTS.md) comes from a
run; the raw per-probe data (including `query_log` rows) is in `results/<version>.json`.

What is probed: `FINAL` on `ReplacingMergeTree` (with and without `is_deleted`), `CollapsingMergeTree`,
`SummingMergeTree` and `AggregatingMergeTree`; the setting `final`; `FINAL` on a view; keys that cross
partitions; `PREWHERE` under `FINAL`; skip indexes under `FINAL`; `FINAL` in a `JOIN`; and the read cost of
`FINAL`, `argMax … GROUP BY` and `LIMIT 1 BY` at 20M rows.

### Run it

```bash
cd workload/final-across-versions
./run_matrix.py                      # all six versions, about 10 minutes; pulls nothing, images must exist
./run_matrix.py --versions 26.10     # one version (prefix of a line in versions.txt)
./run_matrix.py --only 03            # one file or probe-id prefix (a file's results replace that file in the JSON)
./run_matrix.py --report-only        # rebuild RESULTS.md from results/*.json
tools/hol run workload/final-across-versions   # from the repository root: the SQL on 26.10 only, must not raise
```

`versions.txt` pins the exact tags, oldest first. `run_matrix.py` is the runner of
[workload/join-across-versions](../join-across-versions/) with one change: it removes each container with
`docker rm -f -v`, so the anonymous `/var/lib/clickhouse` volume of the image goes with it (without `-v`
every version left about 5 GB behind). Containers are named `fav-<tag>`. A statement preceded by
`-- probe: <id> [repeat=N] [show] [value]` is a probe, the others are setup; `value` puts the first result
row in the table cell, `show` prints the newest version's rows. `-- settings: a, b` lists settings to look
up in `system.settings`. Each statement runs in its own `clickhouse-client` call, so there is no bare `SET`.
Each probe's comment states the correct answer computed from the data.

### Probes

| File | What it does |
|---|---|
| `01-replacing.sql` | `ReplacingMergeTree(ver)` and `(ver, is_deleted)`, 1M keys, 1% re-written with a higher `ver`, 1,000 marked deleted: `count()` without and with `FINAL`, `SETTINGS final = 1` (also through a subquery), a view with `FINAL` inside and `FINAL` on a view without it, `FINAL` vs `argMax … GROUP BY` vs `LIMIT 1 BY`, `enable_vertical_final = 0`, and the FINAL-related rows of `system.settings_changes` |
| `02-engines.sql` | `CollapsingMergeTree` (state, then cancel + new state), `SummingMergeTree((a, b))` with 100 keys whose sums are all zero and 100 where only `a` is zero, `AggregatingMergeTree` with `SimpleAggregateFunction` and `AggregateFunction`, before and after `OPTIMIZE … FINAL` |
| `03-partitions.sql` | a partition key inside the sorting key vs a key that crosses partitions (January row, newer February row): `FINAL`, `do_not_merge_across_partitions_select_final = 1`, `WHERE` on the partition column, `defer_partition_pruning_after_final = 0` |
| `04-prewhere.sql` | `WHERE` vs explicit `PREWHERE` on a non-key column under `FINAL`, `apply_prewhere_after_final = 1`; then 10M rows with a 100-character column and a sorting-key condition the primary key cannot use (`toUInt32(ts) % 86400 < 3600`): time and bytes read with `optimize_move_to_prewhere_if_final` default, 1 and 0, against a `MergeTree` control; whether the plan has a `PREWHERE` |
| `05-skip-index.sql` | 20M rows, a `bloom_filter` index on a non-key column whose value changed for 1% of keys: looking up an **old** value under `FINAL` with `use_skip_indexes_if_final` 0 / 1 and exact mode 0 / 1 (correct answer 0), and a value that did not change |
| `06-join.sql` | a fact table joined to a `ReplacingMergeTree` dimension without `FINAL`, with `FINAL` on the dimension, with `SETTINGS final = 1`; `d1 FINAL JOIN d2` (FINAL on the left table only) and `analyzer_compatibility_apply_final_to_all_joined_tables = 1` |
| `07-scale.sql` | 20M rows, every column `CODEC(LZ4)`: `MergeTree` control, a one-part `ReplacingMergeTree`, 1% and 10% re-written keys, a 16-partition table: `FINAL`, `enable_vertical_final = 0`, `max_final_threads = 1`, `argMax … GROUP BY`, `LIMIT 1 BY`, a 100,000-row range, `do_not_merge_across_partitions_select_final = 1`, `enable_automatic_decision_for_merging_across_partitions_for_final = 0` (5 repeats each) |
| `errors/01-expected-failures.sql` | statements that fail on every build: `FINAL` on a plain `MergeTree` and on a `Memory` table (Code 181), `FINAL SAMPLE` without `SAMPLE BY` (Code 141), `JOIN t FINAL AS d` (Code 62; `JOIN t AS d FINAL` is the form that parses). `tools/hol` does not run this directory; the runner does |

Every probe in the top-level files succeeds on 26.10 (`tools/hol run` stops at the first exception).
Failures on older versions are the result, shown as `✗ Code N`; all of them are Code 115
(UNKNOWN_SETTING), a setting that build does not have yet.

### What changed between versions

Written only from [RESULTS.md](RESULTS.md) (run on 2026-11-05, 12 CPUs, 15.6 GiB Docker VM, no other
container running). The correct answer is in brackets.

- **SummingMergeTree, rows whose sums are all zero.** On 24.8 to 26.8 the row count under `FINAL`
  depended on the columns the query read: `count()` 1,000, `count(), sum(a)` 800, `count(), sum(b)` 900,
  `count(), sum(a), sum(b)` 900 (1,000 rows before the merge). On 26.10.3.7 every form returns 1,000 and
  `countIf(a = 0 AND b = 0)` finds the 100 all-zero keys. `OPTIMIZE … FINAL` drops those 100 rows on every
  build (900 after the merge).
- **A key that crosses partitions, filtered on the partition column.** `FINAL WHERE d < '2026-02-01'`
  returns 1,000,000 on 24.8, 25.3 and 25.8 [990,000]: the February partition, which holds the newer rows of
  10,000 keys, is pruned before `FINAL`, so their January rows win. For key 500 alone the same query returns
  1 row [0]. From 26.3.62.3 the answer is right, at the price of reading the pruned partition too: 1,191,920
  to 1,210,112 rows instead of 1,000,000, and `WHERE d >= '2026-02-01'` reads the same instead of 10,000.
  `defer_partition_pruning_after_final` exists from 26.3 (default 1); setting it to 0 brings back
  1,000,000.
- **`do_not_merge_across_partitions_select_final = 1` on such a table** returns 1,010,000 [1,000,000] on
  every build: the setting is a promise that no key crosses partitions. Where the partition key is a
  function of the sorting key, it returns the right answer on every build.
- **Explicit `PREWHERE` under `FINAL`.** `FINAL PREWHERE v = 1` returns 100,000 on every build [99,000]: the
  filter runs before the merge, so superseded rows pass. `WHERE v = 1` is right on every build with
  `optimize_move_to_prewhere_if_final` 0 or 1 (a non-key condition is not moved). From 26.3,
  `apply_prewhere_after_final = 1` (default 0) makes the explicit `PREWHERE` right.
- **`WHERE` moved to `PREWHERE` under `FINAL`.** `optimize_move_to_prewhere_if_final` is 0 on 24.8 to 26.8
  and 1 on 26.10.3.7. For the sorting-key condition on 10M rows, the default read 1,243,425,772 bytes in
  93 ms on 24.8 and 1,181,744,428 bytes in 82 ms on 26.8; 26.10 read 174,293,428 bytes in 17 ms (median
  of 5). Setting it to 1 on 24.8 already gave 180,606,220 bytes and 23 ms: the optimization existed, the
  default changed. The `MergeTree` control without `FINAL` read 16,416,768 bytes on 26.10.
- **Skip indexes under `FINAL`.** `use_skip_indexes_if_final` is 0 on 24.8 and 25.3 and 1 from 25.8, and
  `use_skip_indexes_if_final_exact_mode` exists from 25.8 (default 1). Looking up a value that only an
  old row version has: with defaults, every build is right (0); 24.8 and 25.3 read 20,380,224 rows, 25.8 to
  26.10 about 4.1M. With `use_skip_indexes_if_final = 1` on 24.8 and 25.3, the answer is wrong (1 [0],
  524,288 rows read); with exact mode 0 on 25.8 to 26.10 it is wrong the same way. Exact mode reads the
  newer parts' ranges again and gets 0.
- **`FINAL` in a `JOIN`.** `dim AS d1 FINAL JOIN dim AS d2` returns 1,000 on 24.8 to 26.3 and 2,000 on 26.8
  and 26.10 [2,000]: on the older builds `FINAL` on the left table was applied to the right one too.
  `analyzer_compatibility_apply_final_to_all_joined_tables = 1` (from 26.8, default 0) gives 1,000 again;
  `system.settings_changes` lists the default change under 26.6. `JOIN dim AS d FINAL` and
  `SETTINGS final = 1` deduplicate the joined table on every build (100,000).
- **`FINAL` on a view.** `SELECT … FROM view FINAL` over a view without `FINAL` runs without error and
  returns the physical 1,010,000 rows on every build [1,000,000]; a view with `FINAL` inside returns
  1,000,000.
- **Unchanged on all six builds:** `ReplacingMergeTree` with and without `is_deleted`, `SETTINGS final = 1`
  (also through a subquery), `CollapsingMergeTree` (state first), `AggregatingMergeTree`, and
  `enable_vertical_final = 0` all give the same answers.

### Read cost at 20M rows (`07-scale.sql`)

Every column is `CODEC(LZ4)`: from 26.9 a part of 100 MB or more defaults to `ZSTD(3)` (the `07-codec`
probe shows `['LZ4','ZSTD(3)']` as part defaults on 26.10.3.7 and `CODEC(LZ4)` as the column codec), so
without the pin the times would compare codecs as well as builds. Median (fastest) of 5 repeats in ms
(`durations_ms` in `results/*.json`); no other container was running.

| Query | 24.8 | 25.3 | 25.8 | 26.3 | 26.8 | 26.10 |
|---|---|---|---|---|---|---|
| `MergeTree`, no `FINAL` | 21 (20) | 38 (29) | 29 (26) | 22 (19) | 38 (24) | 18 (18) |
| one part, `FINAL` | 19 (18) | 24 (23) | 27 (25) | 20 (18) | 21 (18) | 19 (18) |
| 1% re-written, no `FINAL` (wrong answer) | 22 (20) | 27 (24) | 26 (24) | 24 (21) | 24 (23) | 23 (18) |
| 1% re-written, `FINAL` | 82 (73) | 134 (108) | 98 (90) | 101 (90) | 107 (94) | 124 (95) |
| 1%, `FINAL`, `enable_vertical_final = 0` | 113 (98) | 126 (113) | 114 (104) | 92 (85) | 94 (88) | 115 (106) |
| 1%, `FINAL`, `max_final_threads = 1` | 319 (293) | 358 (305) | 305 (298) | 283 (281) | 283 (279) | 391 (350) |
| 1%, `argMax … GROUP BY` | 750 (627) | 861 (376) | 347 (182) | 383 (311) | 203 (163) | 187 (159) |
| 1%, `LIMIT 1 BY` | 4,827 (4,023) | 4,623 (4,279) | 4,321 (4,109) | 514 (454) | 284 (280) | 213 (199) |
| 10% re-written, `FINAL` | 125 (101) | 238 (128) | 114 (97) | 86 (79) | 107 (88) | 88 (85) |
| 10%, `argMax … GROUP BY` | 1,041 (727) | 796 (685) | 349 (309) | 300 (232) | 203 (159) | 167 (159) |
| 1%, 100,000-row range, `FINAL` | 6 (4) | 10 (6) | 5 (4) | 4 (4) | 4 (4) | 4 (4) |
| 16 partitions, `FINAL` | 64 (60) | 84 (68) | 65 (53) | 41 (38) | 40 (38) | 44 (36) |
| same, automatic decision off | ✗ 115 | ✗ 115 | ✗ 115 | 189 (180) | 192 (179) | 198 (185) |

Peak memory: `argMax` at 20M keys 3,970 MiB on 24.8, 2,529 MiB on 25.8, 785 MiB on 26.8, 745 MiB on 26.10;
`LIMIT 1 BY` 2,339 MiB on 24.8 to 25.8 and about 210 MiB from 26.3; `FINAL` 71 to 79 MiB everywhere.

Reading the table: on this data (keys in insert order, two parts) `FINAL` costs about 4x to 5x a plain scan of
the same table on every build and did not get faster between 24.8 and 26.10; it is the cheapest of the three ways to get
the newest row per key on every build. `argMax … GROUP BY` became about 4x faster and 5x leaner, `LIMIT 1 BY`
about 22x faster (the drop is between 25.8 and 26.3). With the partition key a function of the sorting key,
`FINAL` handles partitions separately by default (from 23.12 automatically, from 26.2 through
`enable_automatic_decision_for_merging_across_partitions_for_final`); switching that off made it about 4.5x
slower. A 100,000-row range read on the sorting key takes 10 ms or less with or without `FINAL` on every
build. `max_final_threads = 1` is about 2.6x to 3.9x slower than the default (12 threads).

### Screens

Captured 2026-11-05 from ClickHouse's `/play` UI on local throwaway containers loaded with this lab's files, for
the notes article `core-architecture/clickhouse-final`:

- [`images/01-summing-final-26-8.png`](images/01-summing-final-26-8.png) — `SummingMergeTree` `FINAL` on 26.8.36.3: the row count changes with the columns read (1000, 800, 900, 900)
- [`images/02-summing-final-26-10.png`](images/02-summing-final-26-10.png) — the same query on 26.10.3.7: 1000 in every row
- [`images/03-partition-stale-row-25-8.png`](images/03-partition-stale-row-25-8.png) — `FINAL WHERE d < '2026-02-01'` on 25.8.33.6 returns key 500's superseded January row (`ver` 1)
- [`images/04-prewhere-read-bytes-26-10.png`](images/04-prewhere-read-bytes-26-10.png) — `system.query_log` on 26.10.3.7: the same `FINAL` query read 163.95 MiB by default and 1.10 GiB with `optimize_move_to_prewhere_if_final = 0`
- [`images/05-join-final-left-25-8.png`](images/05-join-final-left-25-8.png) — `d1 FINAL JOIN d2` on 25.8.33.6: 1000, the same as `FINAL` on both sides (26.8 and later: 2000)

### Not verified here

- Distributed or replicated tables, `SharedMergeTree`, parallel replicas and ClickHouse Cloud.
- Keys spread over many parts, many overlapping parts, or tables larger than 20M rows; row policies.
- `query_plan_optimize_lazy_final` (26.8 and 26.10 have it, default 0) and the 26.9 reverse-order read.

Verified on 24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3 and 26.10.3.7, 2026-11-05 (`./run_matrix.py`, all six; `tools/hol run` on 26.10.3.7).

---

## 한국어

같은 `SELECT … FINAL` SQL을 여섯 빌드(LTS 24.8, 25.3, 25.8, 26.3, 26.8과 최신 stable 26.10)에서
실행합니다. probe마다 결과(정답인지), 시간, 읽은 행, 필요한 곳에서는 읽은 바이트를 기록합니다.
[RESULTS.md](RESULTS.md)의 모든 셀은 실행 결과이고, 원시 데이터(`query_log` 행 포함)는
`results/<버전>.json`에 있습니다.

대상: `ReplacingMergeTree`(`is_deleted` 유무), `CollapsingMergeTree`, `SummingMergeTree`,
`AggregatingMergeTree`의 `FINAL`, 설정 `final`, 뷰에 붙인 `FINAL`, 파티션을 넘는 키, `FINAL` 아래의
`PREWHERE`, `FINAL` 아래의 skip index, `JOIN` 속 `FINAL`, 2,000만 행에서 `FINAL` · `argMax … GROUP BY` ·
`LIMIT 1 BY`의 읽기 비용.

### 실행

```bash
cd workload/final-across-versions
./run_matrix.py                      # 여섯 버전 전부, 약 10분. 이미지는 미리 받아 둬야 함
./run_matrix.py --versions 26.10     # 한 버전(versions.txt 줄의 접두사)
./run_matrix.py --only 03            # 파일 또는 probe id 접두사(그 파일의 결과가 JSON에서 통째로 바뀜)
./run_matrix.py --report-only        # results/*.json으로 RESULTS.md 재생성
tools/hol run workload/final-across-versions   # 저장소 루트에서: 26.10에서만 실행, 예외가 없어야 함
```

`versions.txt`는 정확한 태그를 오래된 순으로 고정합니다. `run_matrix.py`는
[workload/join-across-versions](../join-across-versions/)의 러너에서 한 군데만 다릅니다. 컨테이너를
`docker rm -f -v`로 지워 이미지의 익명 볼륨 `/var/lib/clickhouse`도 함께 지웁니다(`-v`가 없으면 버전마다
약 5 GB가 남았습니다). 컨테이너 이름은 `fav-<태그>`입니다. `-- probe: <id> [repeat=N] [show] [value]`가
앞에 붙은 문장이 probe이고 나머지는 준비 문장입니다. `value`는 첫 결과 행을 표 셀에, `show`는 최신
버전의 결과 행을 그대로 넣습니다. `-- settings: a, b`는 `system.settings`에서 찾을 설정입니다. 문장마다
`clickhouse-client`를 따로 호출하므로 단독 `SET`은 쓰지 않습니다. probe마다 주석에 데이터로 계산한
정답을 적었습니다.

### Probe

| 파일 | 내용 |
|---|---|
| `01-replacing.sql` | `ReplacingMergeTree(ver)`, `(ver, is_deleted)`. 키 100만 개, 1%를 더 높은 `ver`로 다시 쓰고 1,000개를 삭제 표시: `FINAL` 유무의 `count()`, `SETTINGS final = 1`(서브쿼리 포함), 안에 `FINAL`이 있는 뷰와 없는 뷰에 붙인 `FINAL`, `FINAL` 대 `argMax … GROUP BY` 대 `LIMIT 1 BY`, `enable_vertical_final = 0`, `system.settings_changes`의 FINAL 관련 행 |
| `02-engines.sql` | `CollapsingMergeTree`(상태 행 뒤 취소 행 + 새 상태 행), 합이 모두 0인 키 100개와 `a`만 0인 키 100개를 둔 `SummingMergeTree((a, b))`, `SimpleAggregateFunction` · `AggregateFunction`의 `AggregatingMergeTree`. `OPTIMIZE … FINAL` 전후 |
| `03-partitions.sql` | 파티션 키가 정렬 키의 함수인 테이블과, 같은 키가 두 파티션에 있는 테이블(1월 행, 더 새로운 2월 행): `FINAL`, `do_not_merge_across_partitions_select_final = 1`, 파티션 컬럼 `WHERE`, `defer_partition_pruning_after_final = 0` |
| `04-prewhere.sql` | `FINAL` 아래에서 키가 아닌 컬럼의 `WHERE` 대 명시적 `PREWHERE`, `apply_prewhere_after_final = 1`. 이어서 100자 컬럼이 있는 1,000만 행에 primary key가 쓰지 못하는 정렬 키 조건(`toUInt32(ts) % 86400 < 3600`): `optimize_move_to_prewhere_if_final` 기본 · 1 · 0의 시간과 읽은 바이트, `MergeTree` 대조군, 계획에 `PREWHERE`가 있는지 |
| `05-skip-index.sql` | 2,000만 행, 키의 1%에서 값이 바뀐 키 아닌 컬럼에 `bloom_filter` 인덱스: `FINAL`로 **옛** 값을 찾기(정답 0)를 `use_skip_indexes_if_final` 0 / 1, exact mode 0 / 1로, 바뀌지 않은 값도 |
| `06-join.sql` | fact 테이블과 `ReplacingMergeTree` 차원 테이블의 조인: `FINAL` 없이, 차원 테이블에 `FINAL`, `SETTINGS final = 1`. 왼쪽에만 `FINAL`을 붙인 `d1 FINAL JOIN d2`, `analyzer_compatibility_apply_final_to_all_joined_tables = 1` |
| `07-scale.sql` | 2,000만 행, 모든 컬럼 `CODEC(LZ4)`: `MergeTree` 대조군, 파트 하나인 `ReplacingMergeTree`, 키 1% · 10% 재기록, 16파티션 테이블: `FINAL`, `enable_vertical_final = 0`, `max_final_threads = 1`, `argMax … GROUP BY`, `LIMIT 1 BY`, 10만 행 범위, `do_not_merge_across_partitions_select_final = 1`, `enable_automatic_decision_for_merging_across_partitions_for_final = 0`(각 5회) |
| `errors/01-expected-failures.sql` | 모든 빌드에서 실패하는 문장: 일반 `MergeTree`와 `Memory`의 `FINAL`(Code 181), `SAMPLE BY` 없는 `FINAL SAMPLE`(Code 141), `JOIN t FINAL AS d`(Code 62, 파싱되는 형태는 `JOIN t AS d FINAL`). `tools/hol`은 이 디렉터리를 실행하지 않고 러너는 실행합니다 |

최상위 파일의 probe는 26.10에서 모두 성공합니다(`tools/hol run`은 첫 예외에서 멈춥니다). 옛 버전의
실패도 결과이며 `✗ Code N`으로 표시합니다. 모두 Code 115(UNKNOWN_SETTING), 그 빌드에 아직 없는
설정입니다.

### 버전 사이에 바뀐 것

[RESULTS.md](RESULTS.md)만 보고 썼습니다(2026-11-05 실행, 12 CPU, 15.6 GiB Docker VM, 다른 컨테이너 없음).
대괄호 안이 정답입니다.

- **SummingMergeTree, 합이 모두 0인 행.** 24.8–26.8에서는 `FINAL`의 행 수가 쿼리가 읽는 컬럼에 따라
  달랐습니다. `count()` 1,000, `count(), sum(a)` 800, `count(), sum(b)` 900, `count(), sum(a), sum(b)`
  900(병합 전 1,000행). 26.10.3.7에서는 모든 형태가 1,000이고 `countIf(a = 0 AND b = 0)`이 합이 0인 키
  100개를 찾습니다. `OPTIMIZE … FINAL`은 모든 빌드에서 그 100행을 지웁니다(병합 뒤 900).
- **파티션을 넘는 키를 파티션 컬럼으로 거를 때.** `FINAL WHERE d < '2026-02-01'`이 24.8 · 25.3 · 25.8에서
  1,000,000을 돌려줍니다[990,000]. 키 1만 개의 새 행이 있는 2월 파티션을 `FINAL` 전에 잘라내서 1월 행이
  최신으로 남습니다. 키 500 하나로 물으면 1행[0]입니다. 26.3.62.3부터는 정답이고, 그 대가로 잘라내던
  파티션도 읽습니다. 1,000,000행 대신 1,191,920–1,210,112행, `WHERE d >= '2026-02-01'`도 10,000행 대신
  같은 양을 읽습니다. `defer_partition_pruning_after_final`은 26.3부터 있고(기본 1) 0으로 두면
  1,000,000으로 돌아갑니다.
- **그런 테이블의 `do_not_merge_across_partitions_select_final = 1`**은 모든 빌드에서
  1,010,000[1,000,000]입니다. 이 설정은 "키가 파티션을 넘지 않는다"는 사용자의 약속입니다. 파티션 키가
  정렬 키의 함수인 테이블에서는 모든 빌드에서 정답이었습니다.
- **`FINAL` 아래의 명시적 `PREWHERE`.** `FINAL PREWHERE v = 1`은 모든 빌드에서 100,000[99,000]입니다.
  필터가 병합 전에 돌아 대체된 옛 행이 통과합니다. `WHERE v = 1`은 `optimize_move_to_prewhere_if_final`
  0과 1 모두 모든 빌드에서 정답입니다(키가 아닌 조건은 옮기지 않음). 26.3부터
  `apply_prewhere_after_final = 1`(기본 0)로 명시적 `PREWHERE`도 정답이 됩니다.
- **`FINAL`에서 `WHERE`를 `PREWHERE`로 옮기기.** `optimize_move_to_prewhere_if_final`은 24.8–26.8에서 0,
  26.10.3.7에서 1입니다. 1,000만 행의 정렬 키 조건에서 기본값으로 24.8은 1,243,425,772바이트 · 93 ms,
  26.8은 1,181,744,428바이트 · 82 ms를 읽었고 26.10은 174,293,428바이트 · 17 ms였습니다(5회 중앙값).
  24.8에서도 1로 두면 180,606,220바이트 · 23 ms였습니다. 최적화는 있었고 기본값이 바뀐 것입니다.
  `FINAL` 없는 `MergeTree` 대조군은 26.10에서 16,416,768바이트였습니다.
- **`FINAL` 아래의 skip index.** `use_skip_indexes_if_final`은 24.8 · 25.3에서 0, 25.8부터 1이고
  `use_skip_indexes_if_final_exact_mode`는 25.8부터 있습니다(기본 1). 옛 행 버전에만 있는 값을 찾으면
  기본값으로는 모든 빌드가 정답(0)이고, 24.8 · 25.3은 20,380,224행, 25.8–26.10은 약 410만 행을 읽었습니다.
  24.8 · 25.3에서 `use_skip_indexes_if_final = 1`을 주면 틀립니다(1[0], 524,288행). 25.8–26.10에서 exact
  mode를 0으로 두면 같은 식으로 틀립니다. exact mode는 더 새로운 파트의 같은 키 범위를 다시 읽어 0을
  냅니다.
- **`JOIN` 속 `FINAL`.** `dim AS d1 FINAL JOIN dim AS d2`가 24.8–26.3에서 1,000, 26.8 · 26.10에서
  2,000입니다[2,000]. 옛 빌드는 왼쪽 테이블의 `FINAL`을 오른쪽에도 적용했습니다.
  `analyzer_compatibility_apply_final_to_all_joined_tables = 1`(26.8부터, 기본 0)이면 다시 1,000이고,
  `system.settings_changes`는 기본값 변경을 26.6에 적어 둡니다. `JOIN dim AS d FINAL`과
  `SETTINGS final = 1`은 모든 빌드에서 조인한 테이블의 중복을 없앱니다(100,000).
- **뷰에 붙인 `FINAL`.** `FINAL`이 없는 뷰에 `SELECT … FROM view FINAL`을 하면 오류 없이 물리 행
  1,010,000을 돌려줍니다(모든 빌드, [1,000,000]). 안에 `FINAL`이 있는 뷰는 1,000,000입니다.
- **여섯 빌드에서 같았던 것:** `is_deleted` 유무의 `ReplacingMergeTree`, `SETTINGS final = 1`(서브쿼리
  포함), `CollapsingMergeTree`(상태 행 먼저), `AggregatingMergeTree`, `enable_vertical_final = 0`의 결과.

### 2,000만 행 읽기 비용(`07-scale.sql`)

모든 컬럼이 `CODEC(LZ4)`입니다. 26.9부터 100 MB 이상 파트의 기본 코덱이 `ZSTD(3)`라(26.10.3.7에서
`07-codec` probe가 파트 기본값 `['LZ4','ZSTD(3)']`, 컬럼 코덱 `CODEC(LZ4)`를 보여 줌), 고정하지 않으면
빌드와 함께 코덱도 비교하게 됩니다. 셀은 5회 중앙값(최솟값) ms(`results/*.json`의 `durations_ms`)이고, 다른 컨테이너는 없었습니다.

| 쿼리 | 24.8 | 25.3 | 25.8 | 26.3 | 26.8 | 26.10 |
|---|---|---|---|---|---|---|
| `MergeTree`, `FINAL` 없음 | 21 (20) | 38 (29) | 29 (26) | 22 (19) | 38 (24) | 18 (18) |
| 파트 하나, `FINAL` | 19 (18) | 24 (23) | 27 (25) | 20 (18) | 21 (18) | 19 (18) |
| 1% 재기록, `FINAL` 없음(틀린 답) | 22 (20) | 27 (24) | 26 (24) | 24 (21) | 24 (23) | 23 (18) |
| 1% 재기록, `FINAL` | 82 (73) | 134 (108) | 98 (90) | 101 (90) | 107 (94) | 124 (95) |
| 1%, `FINAL`, `enable_vertical_final = 0` | 113 (98) | 126 (113) | 114 (104) | 92 (85) | 94 (88) | 115 (106) |
| 1%, `FINAL`, `max_final_threads = 1` | 319 (293) | 358 (305) | 305 (298) | 283 (281) | 283 (279) | 391 (350) |
| 1%, `argMax … GROUP BY` | 750 (627) | 861 (376) | 347 (182) | 383 (311) | 203 (163) | 187 (159) |
| 1%, `LIMIT 1 BY` | 4,827 (4,023) | 4,623 (4,279) | 4,321 (4,109) | 514 (454) | 284 (280) | 213 (199) |
| 10% 재기록, `FINAL` | 125 (101) | 238 (128) | 114 (97) | 86 (79) | 107 (88) | 88 (85) |
| 10%, `argMax … GROUP BY` | 1,041 (727) | 796 (685) | 349 (309) | 300 (232) | 203 (159) | 167 (159) |
| 1%, 10만 행 범위, `FINAL` | 6 (4) | 10 (6) | 5 (4) | 4 (4) | 4 (4) | 4 (4) |
| 16파티션, `FINAL` | 64 (60) | 84 (68) | 65 (53) | 41 (38) | 40 (38) | 44 (36) |
| 같은 테이블, 자동 판단 끔 | ✗ 115 | ✗ 115 | ✗ 115 | 189 (180) | 192 (179) | 198 (185) |

최대 메모리: 키 2,000만 개의 `argMax`가 24.8 3,970 MiB, 25.8 2,529 MiB, 26.8 785 MiB, 26.10 745 MiB.
`LIMIT 1 BY`는 24.8–25.8 2,339 MiB, 26.3부터 약 210 MiB. `FINAL`은 모든 빌드에서 71–79 MiB.

읽는 법: 이 데이터(키가 입력 순서, 파트 두 개)에서 `FINAL`은 모든 빌드에서 같은 테이블 일반 스캔의 약 4–5배였고
24.8과 26.10 사이에 빨라지지 않았습니다. 그래도 키마다 최신 행을 얻는 세 방법 중 모든 빌드에서 가장
쌌습니다. `argMax … GROUP BY`는 약 4배 빨라지고 메모리가 5분의 1이 됐고, `LIMIT 1 BY`는 약 22배
빨라졌습니다(25.8과 26.3 사이). 파티션 키가 정렬 키의 함수이면 `FINAL`은 기본으로 파티션을 따로
처리하고(23.12부터 자동, 26.2부터 `enable_automatic_decision_for_merging_across_partitions_for_final`),
이를 끄면 약 4.5배 느렸습니다. 정렬 키 10만 행 범위 읽기는 `FINAL` 유무와 관계없이 모든 빌드에서 10 ms
이하입니다. `max_final_threads = 1`은 기본값(12 스레드)보다 약 2.6–3.9배 느립니다.

### 화면

2026-11-05에 이 실습의 파일을 넣은 로컬 일회용 컨테이너의 ClickHouse `/play` UI에서 노트 글
`core-architecture/clickhouse-final`용으로 찍었습니다.

- [`images/01-summing-final-26-8.png`](images/01-summing-final-26-8.png) — 26.8.36.3의 `SummingMergeTree` `FINAL`: 읽는 컬럼에 따라 행 수가 1000, 800, 900, 900
- [`images/02-summing-final-26-10.png`](images/02-summing-final-26-10.png) — 같은 쿼리, 26.10.3.7: 모든 행이 1000
- [`images/03-partition-stale-row-25-8.png`](images/03-partition-stale-row-25-8.png) — 25.8.33.6의 `FINAL WHERE d < '2026-02-01'`: 키 500의 대체된 1월 행(`ver` 1)이 나옴
- [`images/04-prewhere-read-bytes-26-10.png`](images/04-prewhere-read-bytes-26-10.png) — 26.10.3.7의 `system.query_log`: 같은 `FINAL` 쿼리가 기본값으로 163.95 MiB, `optimize_move_to_prewhere_if_final = 0`으로 1.10 GiB를 읽음
- [`images/05-join-final-left-25-8.png`](images/05-join-final-left-25-8.png) — 25.8.33.6의 `d1 FINAL JOIN d2`: 양쪽에 `FINAL`을 붙인 것과 같은 1000(26.8 이상은 2000)

### 여기서 확인하지 않은 것

- Distributed · 복제 테이블, `SharedMergeTree`, parallel replicas, ClickHouse Cloud.
- 키가 많은 파트에 흩어진 경우, 서로 겹치는 파트가 많은 경우, 2,000만 행보다 큰 테이블, row policy.
- `query_plan_optimize_lazy_final`(26.8 · 26.10에 있음, 기본 0)과 26.9의 역순 읽기.

Verified on 24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3 and 26.10.3.7, 2026-11-05 (`./run_matrix.py`, all six; `tools/hol run` on 26.10.3.7).
