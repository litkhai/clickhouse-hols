# Indexes across ClickHouse versions

[English](#english) | [한국어](#한국어)

---

## English

The same index SQL run on six builds (the LTS lines 24.8, 25.3, 25.8, 26.3, 26.8 and the latest stable 26.10).
The main measure is how much each query reads: the granules that `EXPLAIN indexes = 1` selects and `read_rows`
from `system.query_log`. Times are recorded only for the 20M-row tables, as the minimum of 5 runs. Every cell in
[RESULTS.md](RESULTS.md) comes from a run; the raw per-probe data (including `query_log` rows) is in
`results/<version>.json`.

What is probed: the primary index (a condition on the first sorting-key column, on the second column only,
on a function of the key, on a non-key column, `use_primary_key = 0`); skip indexes on non-key columns (`minmax`
on a correlated and an uncorrelated column, `set(100)` vs `set(0)`, `bloom_filter` with `GRANULARITY` 1 and 4,
`tokenbf_v1` at two sizes, `ngrambf_v1`, `!=`, `NOT`, `OR`, a value-preserving cast); the `text` index (`hasToken`,
`hasAnyTokens`, `hasAllTokens`, `LIKE`, `=`, `NOT`, direct read, index size and posting-list codec); automatic minmax
indices; the query condition cache; a skip index under `FINAL`; index sizes; and the statements each build rejects.

### Run it

```bash
cd workload/index-across-versions
./run_matrix.py                      # all six versions, about 20 minutes; pulls nothing, images must exist
./run_matrix.py --versions 26.10     # one version (prefix of a line in versions.txt)
./run_matrix.py --only 03            # one file or probe-id prefix (a file's results replace that file in the JSON)
./run_matrix.py --report-only        # rebuild RESULTS.md from results/*.json
tools/hol run workload/index-across-versions   # from the repository root: the SQL on 26.10 only, must not raise
```

`versions.txt` pins the exact tags, oldest first. `run_matrix.py` is the same file as in
[workload/final-across-versions](../final-across-versions/), [workload/join-across-versions](../join-across-versions/)
and [workload/upsert-across-versions](../upsert-across-versions/); it removes each container with `docker rm -f -v`.
Containers are named `iav-<tag>`. A statement preceded by `-- probe: <id> [repeat=N] [show] [value]` is a probe, the
others are setup; `value` puts the first result row in the table cell, `show` prints the newest version's rows.
`-- settings: a, b` lists settings to look up in `system.settings` (then `system.merge_tree_settings`). Each statement
runs in its own `clickhouse-client` call, so there is no bare `SET`. Each probe's comment states the correct answer
computed from the data. A setup statement that fails skips the rest of its file, so statements that only newer builds
accept sit at the end of a file.

Granules come from a probe named `<id>-g` that keeps the `PrimaryKey`, `Skip`, `Name:`, `Granules:` and
`Search Algorithm:` lines of `EXPLAIN indexes = 1` for the same query (26.8 and 26.10 draw the plan as a tree, so the
probe strips the `│ └ ├ ─` prefixes first).

### Probes

| File | What it does |
|---|---|
| `01-primary.sql` | 8,192,000 rows (1,000 granules), `ORDER BY (a, b)` with a 10-value `a` and with a 100,000-value `a`, and `ORDER BY ts`: `a = 3`, `b = …` alone, `a AND b`, `a IN`, a non-key column, a time range, `toDate(ts)`, `toHour(ts)`, `use_primary_key = 0` (26.1+, last) |
| `02-skip.sql` | 8,192,000 rows, `ORDER BY id`, one table with eleven indexed non-key columns: `minmax` (correlated / uncorrelated), `set(100)` / `set(0)` on ~8,000 values per granule, `bloom_filter` `GRANULARITY` 1 / 4, `tokenbf_v1(32768, 3, 0)` and `(1024, 2, 0)`, `ngrambf_v1(4, 32768, 3, 0)`; equality, `IN`, `!=`, `NOT`, `LIKE`, 3-character `LIKE`, `OR` across two indexes, `toNullable(uid) = …`; index and part sizes |
| `03-text.sql` | 20,000,000 rows, `text(tokenizer = splitByNonAlpha)`: default granularity, size against the part, `hasToken` / `hasAnyTokens` / `hasAllTokens` / `LIKE` / `LIKE` on a substring / `=` / `NOT` / a frequent token, a column read through the index, `use_skip_indexes = 0`, `query_plan_direct_read_from_text_index = 0`; then `posting_list_codec = 'bitpacking'` and `'pfor'` (last). Fails at `CREATE` on 24.8–25.8 |
| `04-auto-minmax.sql` | `add_minmax_index_for_numeric_columns = 1` and `add_minmax_index_for_string_columns = 1` against the same table without them: the indices created, ranges on a correlated `UInt32` and `String`, a `DateTime` range; then `add_minmax_index_for_temporal_columns = 1` (last). Fails at `CREATE` on 24.8 |
| `05-condition-cache.sql` | a selective filter on a non-key column run twice with the default, with `use_query_condition_cache = 0` and `= 1`; `system.query_condition_cache` entries; the count after an `INSERT`; then a lightweight `UPDATE` between two runs (last; 25.7+) |
| `06-final.sql` | 1,000,000-row `ReplacingMergeTree` with a `bloom_filter` index, 1% of keys re-written: an old and a new value under `FINAL`, `use_skip_indexes_if_final = 0` (the full matrix is `final-across-versions/05-skip-index.sql`) |
| `07-scale.sql` | 20,000,000 rows, every column `CODEC(LZ4)`: primary-key point lookup, `bloom_filter` lookup, `tokenbf_v1` `hasToken`, each with `use_skip_indexes = 0`, and a scan on a non-key column; every probe also with `use_query_condition_cache = 0` (5 repeats each); part and column codec; index sizes; then a control with the table default codec pinned to LZ4 (last, 25.8+) |
| `errors/01-expected-failures.sql` | `force_primary_key` and `force_data_skipping_indices` refusals (Code 277), the index type names of each generation (`inverted`, `full_text`, `text(tokenizer = 'default')`, `text` without a tokenizer), a `text` index on `UInt64`, `MergeTree` without `ORDER BY`. `tools/hol` does not run this directory; the runner does |

Tables of 1M rows or more carry `CODEC(LZ4)` on every column: from 26.9 a part of 100 MiB or more defaults to
`ZSTD(3)` (ClickHouse#108786), older builds write LZ4, so without the pin the sizes and times would compare codecs
as well as builds. `07-codec` shows the part default and the column codec on each build.

### What the runs show

Run 2026-11-05 on one 12-CPU, 15.6 GiB Docker VM, a fresh container per build. Another session's containers
(`lf-gateway-lab-*`) were running at 0–100% of 1,200% CPU when each build's run started (table in RESULTS.md).
Granules are `selected/total` from `EXPLAIN indexes = 1`; rows are `read_rows`.

**Primary index — the same on all six builds.** On `ORDER BY (a, b)` with 1,000 granules: `a = 3` selects 101,
`a AND b` 1, `a IN (3, 7)` 202. A condition on `b` alone selects 19 when `a` has 10 values and 1,000 when it has
100,000 (generic exclusion search; the `Search Algorithm:` line appears from the 25.8 build). On `ORDER BY ts`:
a one-day range and `toDate(ts) = …` both 12, `toHour(ts) = 3` 231 (not all: the function is monotonic within
a granule's range, so granules whose range cannot contain hour 3 are excluded), a non-key column 1,000.
`use_primary_key = 0` exists from the 26.3 build and selects 1,000. `count()` with a key condition read only the
boundary granules on every build (16,385 rows for 819,200 matching).

**Skip indexes.**

| Probe (8,192,000 rows, 1,000 granules) | 24.8–26.3 | 26.8, 26.10 |
|---|---|---|
| `minmax`, correlated column, `=` / range | 1 / 2 | 1 / 2 |
| `minmax`, uncorrelated column, `=` / range | 998 / 1,000 | 998 / 1,000 |
| `set(100)`, value absent, ~8,000 distinct per granule | 1,000 (8,192,000 rows) | 0 rows (part pruned by statistics) |
| `set(0)`, same value | 0 | 0 rows (part pruned by statistics) |
| `bloom_filter`, one value / `IN` 3 values / `!=` | 27 / 83 / 1,000 | same |
| `bloom_filter GRANULARITY 4`, one value | 28 | 28 |
| `toNullable(uid) = …` | 1,000 | 27 |
| `tokenbf_v1(32768, 3, 0)`: `hasToken` / `LIKE '%timeout%'` / `NOT hasToken` | 9 / 1,000 / 1,000 | same |
| `tokenbf_v1(1024, 2, 0)`, `hasToken` | 825 | 825 |
| `ngrambf_v1(4, …)`: `LIKE '%timeout%'` / `'%imeou%'` / `'%eou%'` / `hasToken` | 9 / 9 / 1,000 / 9 | same |
| `uid = … OR cat = 'rare'` (two indexes) | 24.8–25.8: 1,000; 26.3: 28 | 28 |

- On 26.8 and 26.10 the `set` probes read 0 rows for a different reason: `EXPLAIN` shows a `Statistics` step
  (`Granules: 0/1000`) before `PrimaryKey`. Column statistics are built automatically (`auto_statistics_types`
  `basic, uniq_v2`; `system.settings_changes` lists the default from 26.4, as is `use_statistics_for_part_pruning = 1`),
  and the value 100001 is outside the column's range, so the whole part is skipped. The 26.3 build reads all 1,000
  granules. The `set(100)` result on ≤26.3 is the one the index itself gives: a granule with more distinct values than
  the limit cannot be skipped. `set(0)` (no limit) works but its index is 30.1 MiB against 67 bytes.
- `toNullable(uid) = …` uses the index from the 26.8 build: ClickHouse#123239 (26.10), backported to 26.8 as #123727.
- `OR` across two indexes is `<Combined skip indexes>` from the 26.3 build (25.12 changelog,
  `use_skip_indexes_for_disjunctions`); 25.8 reads all 8,192,000 rows.
- `tokenbf_v1` does not serve `LIKE '%word%'`; `ngrambf_v1` does, down to `n` characters. With the parameters
  `(1024, 2, 0)` the token filter kept 825 of 1,000 granules (too small for ~9,000 tokens per granule).
- Index sizes on 24.8–26.8: `i_tok` 25.7 MiB, `i_ngr` 26.3 MiB, `i_uid` 7.8 MiB, `i_tok_small` 0.81 MiB; 26.10 16.6,
  15.6, 7.6 and 0.51 MiB. The columns are pinned to `CODEC(LZ4)`, but the index files take the part's default codec,
  which is `ZSTD(3)` on 26.10 for this 440 MiB part.

**`text` index (26.3+; 20,000,000 rows, 2,442 granules).** Default granularity 100,000,000 (one index block per
part). `hasToken`, `hasAnyTokens`, `hasAllTokens` select 20 granules (163,840 rows); `msg = …` 1; `NOT hasToken` all.
`count()` with `hasToken` is answered from the index on 26.8 and 26.10 (16 and 0 bytes read; 26.10 still reports
`read_rows` 20,000,000). `LIKE '%timeout%'` and `LIKE '%imeou%'`: 26.3 reads all 2,442 granules (975,578,100 bytes,
31 ms), 26.8 and 26.10 select 20 (4–5 ms) — the 26.4 changelog has "`LIKE` queries … can use text indices" (#98149).
Without the index (`use_skip_indexes = 0`) the same lookup takes 25–31 ms, with it 1–2 ms. Size: the default
index was 233.3 MiB (26.3, 26.8) and 232.9 MiB (26.10) against a 225.4 MiB data part; `posting_list_codec = 'bitpacking'`
87.5 MiB (26.3), 97.6 MiB (26.8), 97.2 MiB (26.10); `'pfor'` 40.0 MiB (26.10 only; 26.8 rejects it with Code 36).

**Index type names per build** (`errors/`): `inverted` is refused on 24.8 and 25.3 (Code 127, "use `full_text`");
`full_text` is accepted on 25.3 with `allow_experimental_full_text_index = 1` in the `CREATE`'s `SETTINGS`, on 24.8
only after a session `SET` (checked by hand); 25.8 accepts `text(tokenizer = 'default')` (experimental); from 26.3
`text` needs a tokenizer (Code 36) and `'default'` is unknown. `MergeTree` without `ORDER BY` is refused on ≤25.8
(Code 42) and accepted from 26.3 (`create_table_empty_primary_key_by_default`, 25.11). `force_primary_key` and
`force_data_skipping_indices` refuse with Code 277 on every build.

**Automatic minmax indices (25.3+).** `add_minmax_index_for_numeric_columns = 1` and `…_string_columns = 1` create
`auto_minmax_index_id`, `…_s`, `…_v`: a range on the correlated `UInt32` selects 2 of 1,000 granules (1,000 without),
the `String` 1. A `DateTime` range is not covered (1,000) until `add_minmax_index_for_temporal_columns = 1`
(from the 26.3 build): 12. 24.8 does not know the settings (Code 115).

**Query condition cache.** The second run of a selective filter on a non-key column read 262,144 rows instead of
8,192,000 from the 25.8 build (default on; 25.4 changelog). 25.3 has the setting with default 0; with `= 1` the
second run read 196,608. After an `INSERT` of 1,000 matching rows the count was right (1,004) and 263,144 rows were
read. A lightweight `UPDATE` between two runs gave 4 then 5, correct, on every build that has `UPDATE` (25.8+).
At 20M rows the cache made a repeated lookup without any index as cheap as with one (below).

**Skip index under `FINAL`.** 24.8 and 25.3 do not use the index under `FINAL` by default (1,210,112 rows read);
from 25.8 they do (171,072), and `EXPLAIN` adds a `PrimaryKeyExpand` step (5 → 14 granules, the same key ranges in
the other part). Answers are correct on every build. With `use_skip_indexes_if_final = 0`, ≤26.3 read 1,210,112 rows
in both runs of the matrix; 26.8 and 26.10 read fewer and the number differed between the two runs (1,137,344–1,191,920).
Not the cache (the same with it off, by hand on 26.10); not investigated further.

### 20M-row lookups (`07-scale.sql`)

Minimum of 5 runs in ms (`durations_ms` in `results/*.json`), `use_query_condition_cache = 0` (24.8 has no cache;
its cell is the run without the setting). All columns `CODEC(LZ4)`.

| Query | 24.8 | 25.3 | 25.8 | 26.3 | 26.8 | 26.10 | 26.10, table default LZ4 |
|---|---|---|---|---|---|---|---|
| primary key `id = …` | 1 | 1 | 1 | 2 | 1 | 1 | |
| `bloom_filter` `uid = …` (475,136 rows) | 4 | 5 | 4 | 5 | 5 | 18 | 5 |
| same, `use_skip_indexes = 0` (20M rows) | 5 | 7 | 6 | 5 | 6 | 5 | |
| `tokenbf_v1` `hasToken` (163,840 rows) | 38 | 40 | 38 | 35 | 37 | 67 | 37 |
| same, `use_skip_indexes = 0` | 45 | 43 | 32 | 29 | 25 | 23 | |
| non-key column, no index | 4 | 4 | 4 | 4 | 4 | 4 | |

- 26.10's slower index lookups are the index files' codec: the part default is `ZSTD(3)` (`07-codec`), so the
  `tokenbf` index is 40.6 MiB instead of 62.9 MiB and slower to read. Pinning the table's
  `default_compression_codec = 'LZ4'` (`big_lz4`, the table setting exists from the 25.8 build) gives 37 and 5 ms.
- A `bloom_filter` on a 64-bit hash saved nothing here: 4–5 ms with it, 5–7 ms without. The `tokenbf` on a string
  column was slower than scanning it on 25.8–26.10 (35–38 ms against 23–32 ms): reading 63 MiB of filter costs more
  than the scan it avoids. The `text` index (`03-text.sql`) answered the same lookup in 1–2 ms.
- With the cache on (the default from 25.8), a repeated lookup with no index took 1–3 ms (65,536 / 327,680 rows).

### Screens

Captured on 2026-11-05 from the ClickHouse `/play` UI of local throwaway containers loaded with this lab's
files, for the notes article `core-architecture/clickhouse-index`.

- [`images/01-explain-generic-exclusion-26-10.png`](images/01-explain-generic-exclusion-26-10.png) — 26.10.3.7, `b = 5000003` on `ORDER BY (a, b)` with a 10-value `a`: 19/1000 granules, generic exclusion search
- [`images/02-or-skip-indexes-25-8.png`](images/02-or-skip-indexes-25-8.png) — 25.8.33.6, `uid = … OR cat = 'rare'`: only `i_uid` analysed, 1000/1000
- [`images/03-or-skip-indexes-26-10.png`](images/03-or-skip-indexes-26-10.png) — the same on 26.10.3.7: `<Combined skip indexes>` 28/1000
- [`images/04-statistics-part-pruning-26-10.png`](images/04-statistics-part-pruning-26-10.png) — 26.10.3.7, `many = 100001` (outside the column's range): `Statistics` 0/1000 before the primary key and the `set(100)` index
- [`images/05-text-index-size-26-10.png`](images/05-text-index-size-26-10.png) — 26.10.3.7, the `text` index on 20M rows: 232.89 MiB (default), 97.24 MiB (`bitpacking`), 40.00 MiB (`pfor`), data part 225.41 MiB
- [`images/06-condition-cache-26-10.png`](images/06-condition-cache-26-10.png) — 26.10.3.7, `system.query_log` for `count() WHERE v = 7` run twice and once with the cache off: 8,192,000 / 262,144 / 8,192,000 rows

### Not covered here

- Distributed and replicated tables, `SharedMergeTree`, parallel replicas, ClickHouse Cloud.
- Projections, `vector_similarity` indexes, column statistics as a query-planning input (only their part pruning
  showed up), tokenizers other than `splitByNonAlpha` (see `usecase/fulltext-search` and
  `usecase/korean-rag-tokenizers`), phrase search, data larger than 20M rows, many parts per table.

---

## 한국어

같은 인덱스 SQL을 빌드 여섯 개(LTS 24.8, 25.3, 25.8, 26.3, 26.8과 최신 안정판 26.10)에서 실행합니다. 주된 척도는
쿼리마다 읽는 양입니다. `EXPLAIN indexes = 1`이 고른 granule 수와 `system.query_log`의 `read_rows`입니다. 시간은
2,000만 행 테이블에서만 5회 최솟값으로 기록합니다. [RESULTS.md](RESULTS.md)의 모든 셀은 실행 결과이고, probe별 원자료
(`query_log` 행 포함)는 `results/<버전>.json`에 있습니다.

확인하는 것: 기본 인덱스(정렬 키 첫 컬럼 조건, 둘째 컬럼만의 조건, 키의 함수, 키가 아닌 컬럼, `use_primary_key = 0`),
키가 아닌 컬럼의 skip index(상관 있는 컬럼과 없는 컬럼의 `minmax`, `set(100)`과 `set(0)`, `GRANULARITY` 1 · 4의
`bloom_filter`, 크기 두 가지의 `tokenbf_v1`, `ngrambf_v1`, `!=`, `NOT`, `OR`, 값을 바꾸지 않는 캐스트), `text` 인덱스
(`hasToken`, `hasAnyTokens`, `hasAllTokens`, `LIKE`, `=`, `NOT`, direct read, 인덱스 크기와 posting list 코덱), 자동 minmax
인덱스, query condition cache, `FINAL` 아래의 skip index, 인덱스 크기, 빌드마다 거부되는 문장.

### 실행

```bash
cd workload/index-across-versions
./run_matrix.py                      # 여섯 버전 전부, 약 20분; 이미지를 받지 않으므로 미리 있어야 함
./run_matrix.py --versions 26.10     # 한 버전(versions.txt 줄의 접두사)
./run_matrix.py --only 03            # 파일이나 probe id 접두사 하나(그 파일의 결과만 JSON에서 바뀜)
./run_matrix.py --report-only        # results/*.json에서 RESULTS.md만 다시 만듦
tools/hol run workload/index-across-versions   # 저장소 루트에서: 26.10에서만 SQL 실행, 오류가 없어야 함
```

`versions.txt`는 정확한 태그를 오래된 순으로 고정합니다. `run_matrix.py`는
[workload/final-across-versions](../final-across-versions/), [workload/join-across-versions](../join-across-versions/),
[workload/upsert-across-versions](../upsert-across-versions/)와 같은 파일이고, 컨테이너를 `docker rm -f -v`로 지웁니다.
컨테이너 이름은 `iav-<태그>`입니다. `-- probe: <id> [repeat=N] [show] [value]` 바로 뒤의 문장이 probe이고 나머지는
준비 문장입니다. `value`는 결과 첫 행을 표 셀에, `show`는 최신 버전의 결과 행을 출력합니다. `-- settings: a, b`는
`system.settings`(없으면 `system.merge_tree_settings`)에서 찾을 설정입니다. 문장마다 `clickhouse-client`를 따로 부르므로
단독 `SET`은 쓰지 않습니다. probe 주석에는 데이터로 계산한 정답이 있습니다. 준비 문장이 실패하면 그 파일의 나머지가
건너뛰어지므로, 새 빌드만 받는 문장은 파일 끝에 둡니다.

granule 수는 같은 쿼리의 `EXPLAIN indexes = 1`에서 `PrimaryKey`, `Skip`, `Name:`, `Granules:`, `Search Algorithm:` 줄만
남기는 `<id>-g` probe가 냅니다(26.8 · 26.10은 계획을 트리로 그려서 `│ └ ├ ─` 접두사를 먼저 지움).

### Probe

| 파일 | 하는 일 |
|---|---|
| `01-primary.sql` | 8,192,000행(granule 1,000개), 값 10개인 `a`와 값 100,000개인 `a`의 `ORDER BY (a, b)`, `ORDER BY ts`: `a = 3`, `b = …`만, `a AND b`, `a IN`, 키가 아닌 컬럼, 시간 범위, `toDate(ts)`, `toHour(ts)`, `use_primary_key = 0`(26.1+, 마지막) |
| `02-skip.sql` | 8,192,000행, `ORDER BY id`, 키가 아닌 컬럼 11개에 인덱스: `minmax`(상관 있음 / 없음), granule당 약 8,000값 컬럼의 `set(100)` / `set(0)`, `bloom_filter` `GRANULARITY` 1 / 4, `tokenbf_v1(32768, 3, 0)`과 `(1024, 2, 0)`, `ngrambf_v1(4, 32768, 3, 0)`; 등호, `IN`, `!=`, `NOT`, `LIKE`, 3글자 `LIKE`, 인덱스 두 개에 걸친 `OR`, `toNullable(uid) = …`; 인덱스와 파트 크기 |
| `03-text.sql` | 20,000,000행, `text(tokenizer = splitByNonAlpha)`: 기본 granularity, 파트 대비 크기, `hasToken` / `hasAnyTokens` / `hasAllTokens` / `LIKE` / 부분 문자열 `LIKE` / `=` / `NOT` / 흔한 토큰, 인덱스로 다른 컬럼 읽기, `use_skip_indexes = 0`, `query_plan_direct_read_from_text_index = 0`; 이어서 `posting_list_codec = 'bitpacking'`과 `'pfor'`(마지막). 24.8–25.8은 `CREATE`에서 실패 |
| `04-auto-minmax.sql` | `add_minmax_index_for_numeric_columns = 1` · `add_minmax_index_for_string_columns = 1`과 설정 없는 같은 테이블: 만들어진 인덱스, 상관 있는 `UInt32` · `String` 범위, `DateTime` 범위; 이어서 `add_minmax_index_for_temporal_columns = 1`(마지막). 24.8은 `CREATE`에서 실패 |
| `05-condition-cache.sql` | 키가 아닌 컬럼의 선택적 필터를 기본값, `use_query_condition_cache = 0`, `= 1`로 두 번씩; `system.query_condition_cache` 항목 수; `INSERT` 뒤 개수; 두 실행 사이의 lightweight `UPDATE`(마지막, 25.7+) |
| `06-final.sql` | 100만 행 `ReplacingMergeTree`에 `bloom_filter` 인덱스, 키 1% 재기록: `FINAL` 아래 옛 값과 새 값, `use_skip_indexes_if_final = 0`(전체 매트릭스는 `final-across-versions/05-skip-index.sql`) |
| `07-scale.sql` | 20,000,000행, 모든 컬럼 `CODEC(LZ4)`: 기본 키 점 조회, `bloom_filter` 조회, `tokenbf_v1` `hasToken`과 각각의 `use_skip_indexes = 0`, 키가 아닌 컬럼 스캔; 모든 probe를 `use_query_condition_cache = 0`으로도(각 5회); 파트 · 컬럼 코덱; 인덱스 크기; 이어서 테이블 기본 코덱을 LZ4로 고정한 대조군(마지막, 25.8+) |
| `errors/01-expected-failures.sql` | `force_primary_key` · `force_data_skipping_indices` 거부(Code 277), 세대별 인덱스 타입 이름(`inverted`, `full_text`, `text(tokenizer = 'default')`, 토크나이저 없는 `text`), `UInt64`에 `text` 인덱스, `ORDER BY` 없는 `MergeTree`. `tools/hol`은 이 디렉터리를 돌리지 않고 러너는 돌림 |

100만 행 이상 테이블은 모든 컬럼에 `CODEC(LZ4)`를 붙였습니다. 26.9부터 100 MiB 이상 파트의 기본 코덱이 `ZSTD(3)`이고
(ClickHouse#108786) 옛 빌드는 LZ4라서, 고정하지 않으면 빌드와 함께 코덱도 비교하게 됩니다. `07-codec`이 빌드마다
파트 기본값과 컬럼 코덱을 보여 줍니다.

### 결과

2026-11-05, 12 CPU · 15.6 GiB Docker VM 한 대에서 빌드마다 새 컨테이너로 실행했습니다. 다른 세션의 컨테이너
(`lf-gateway-lab-*`)가 각 빌드 실행 시작 시점에 1,200% 중 0–100% CPU로 돌고 있었습니다(RESULTS.md 표).
granule은 `EXPLAIN indexes = 1`의 `고른 수/전체`, 행은 `read_rows`입니다.

**기본 인덱스 — 여섯 빌드 모두 같음.** granule 1,000개의 `ORDER BY (a, b)`에서 `a = 3`은 101, `a AND b`는 1,
`a IN (3, 7)`은 202개를 고릅니다. `b`만의 조건은 `a`가 값 10개일 때 19, 값 100,000개일 때 1,000입니다(generic exclusion
search; `Search Algorithm:` 줄은 25.8 빌드부터 나옴). `ORDER BY ts`에서 하루 범위와 `toDate(ts) = …`는 둘 다 12,
`toHour(ts) = 3`은 231입니다(전부가 아님: 함수가 granule 범위 안에서는 단조라, 3시를 담을 수 없는 granule은 제외됨).
키가 아닌 컬럼은 1,000입니다. `use_primary_key = 0`은 26.3 빌드부터 있고 1,000을 고릅니다. 키 조건이 있는 `count()`는
모든 빌드에서 경계 granule만 읽었습니다(일치 819,200행에 16,385행).

**Skip index.**

| Probe(8,192,000행, granule 1,000개) | 24.8–26.3 | 26.8, 26.10 |
|---|---|---|
| `minmax`, 상관 있는 컬럼, `=` / 범위 | 1 / 2 | 1 / 2 |
| `minmax`, 상관 없는 컬럼, `=` / 범위 | 998 / 1,000 | 998 / 1,000 |
| `set(100)`, 없는 값, granule당 약 8,000값 | 1,000(8,192,000행) | 0행(통계로 파트 제외) |
| `set(0)`, 같은 값 | 0 | 0행(통계로 파트 제외) |
| `bloom_filter`, 값 하나 / `IN` 3개 / `!=` | 27 / 83 / 1,000 | 같음 |
| `bloom_filter GRANULARITY 4`, 값 하나 | 28 | 28 |
| `toNullable(uid) = …` | 1,000 | 27 |
| `tokenbf_v1(32768, 3, 0)`: `hasToken` / `LIKE '%timeout%'` / `NOT hasToken` | 9 / 1,000 / 1,000 | 같음 |
| `tokenbf_v1(1024, 2, 0)`, `hasToken` | 825 | 825 |
| `ngrambf_v1(4, …)`: `LIKE '%timeout%'` / `'%imeou%'` / `'%eou%'` / `hasToken` | 9 / 9 / 1,000 / 9 | 같음 |
| `uid = … OR cat = 'rare'`(인덱스 두 개) | 24.8–25.8: 1,000; 26.3: 28 | 28 |

- 26.8 · 26.10의 `set` probe가 0행인 이유는 다릅니다. `EXPLAIN`에 `PrimaryKey` 앞의 `Statistics` 단계
  (`Granules: 0/1000`)가 있습니다. 컬럼 통계가 자동으로 만들어지고(`auto_statistics_types` `basic, uniq_v2`;
  `system.settings_changes`는 기본값을 26.4에 적고, `use_statistics_for_part_pruning = 1`도 26.4), 값 100001이 컬럼
  범위 밖이라 파트 전체가 빠집니다. 26.3 빌드는 1,000개를 모두 읽습니다. ≤26.3의 `set(100)` 결과가 인덱스 자체의
  동작입니다. 고유값이 한도보다 많은 granule은 건너뛸 수 없습니다. `set(0)`(한도 없음)은 동작하지만 인덱스가 67바이트
  대신 30.1 MiB입니다.
- `toNullable(uid) = …`는 26.8 빌드부터 인덱스를 씁니다. ClickHouse#123239(26.10)가 #123727로 26.8에 백포트됐습니다.
- 인덱스 두 개에 걸친 `OR`는 26.3 빌드부터 `<Combined skip indexes>`입니다(25.12 changelog,
  `use_skip_indexes_for_disjunctions`). 25.8은 8,192,000행을 모두 읽습니다.
- `tokenbf_v1`은 `LIKE '%word%'`에 쓰이지 않고, `ngrambf_v1`은 `n`글자까지 쓰입니다. `(1024, 2, 0)` 파라미터의 토큰
  필터는 granule 1,000개 중 825개를 남겼습니다(granule당 토큰 약 9,000개에 비해 너무 작음).
- 인덱스 크기(24.8–26.8): `i_tok` 25.7 MiB, `i_ngr` 26.3 MiB, `i_uid` 7.8 MiB, `i_tok_small` 0.81 MiB; 26.10은 16.6,
  15.6, 7.6, 0.51 MiB. 컬럼은 `CODEC(LZ4)`로 고정했지만 인덱스 파일은 파트 기본 코덱을 따르고, 26.10에서 이 440 MiB
  파트의 기본값은 `ZSTD(3)`입니다.

**`text` 인덱스(26.3+, 2,000만 행, granule 2,442개).** 기본 granularity는 100,000,000(파트당 인덱스 블록 하나)입니다.
`hasToken`, `hasAnyTokens`, `hasAllTokens`는 granule 20개(163,840행), `msg = …`는 1개, `NOT hasToken`은 전부를 고릅니다.
`hasToken`의 `count()`는 26.8 · 26.10에서 인덱스로 답합니다(읽은 바이트 16, 0; 26.10은 그래도 `read_rows`
20,000,000을 기록). `LIKE '%timeout%'` · `LIKE '%imeou%'`는 26.3에서 2,442개를 모두 읽고(975,578,100바이트, 31 ms),
26.8 · 26.10은 20개를 고릅니다(4–5 ms). 26.4 changelog에 "`LIKE` queries … can use text indices"(#98149)가 있습니다.
인덱스 없이(`use_skip_indexes = 0`) 같은 조회가 25–31 ms, 인덱스로 1–2 ms입니다. 크기: 기본 인덱스는 233.3 MiB(26.3,
26.8) · 232.9 MiB(26.10)로 데이터 파트 225.4 MiB보다 컸습니다. `posting_list_codec = 'bitpacking'`은 87.5 MiB(26.3),
97.6 MiB(26.8), 97.2 MiB(26.10), `'pfor'`는 40.0 MiB(26.10만; 26.8은 Code 36으로 거부).

**빌드별 인덱스 타입 이름**(`errors/`): `inverted`는 24.8 · 25.3에서 거부(Code 127, "`full_text`를 쓰라"). `full_text`는
25.3에서 `CREATE`의 `SETTINGS`에 `allow_experimental_full_text_index = 1`을 주면 되고, 24.8은 세션 `SET` 뒤에만 됩니다
(손으로 확인). 25.8은 `text(tokenizer = 'default')`(실험 기능)를 받습니다. 26.3부터 `text`에는 토크나이저가 필요하고
(Code 36) `'default'`는 알 수 없는 토크나이저입니다. `ORDER BY` 없는 `MergeTree`는 ≤25.8에서 거부(Code 42), 26.3부터
허용(`create_table_empty_primary_key_by_default`, 25.11). `force_primary_key` · `force_data_skipping_indices`는 모든 빌드에서
Code 277로 거부합니다.

**자동 minmax 인덱스(25.3+).** `add_minmax_index_for_numeric_columns = 1`과 `…_string_columns = 1`은
`auto_minmax_index_id`, `…_s`, `…_v`를 만듭니다. 상관 있는 `UInt32` 범위가 granule 1,000개 중 2개(설정 없으면 1,000),
`String`은 1개입니다. `DateTime` 범위는 `add_minmax_index_for_temporal_columns = 1`(26.3 빌드부터) 전까지 대상이 아니고
(1,000), 켜면 12입니다. 24.8은 설정을 모릅니다(Code 115).

**Query condition cache.** 키가 아닌 컬럼의 선택적 필터를 두 번째로 돌리면 25.8 빌드부터 8,192,000행 대신 262,144행을
읽었습니다(기본 켜짐; 25.4 changelog). 25.3에는 설정이 있고 기본 0이며, `= 1`이면 두 번째 실행이 196,608행이었습니다.
일치하는 1,000행을 `INSERT`한 뒤 개수는 맞았고(1,004) 263,144행을 읽었습니다. 두 실행 사이의 lightweight `UPDATE`는
`UPDATE`가 있는 모든 빌드(25.8+)에서 4, 5로 맞았습니다. 2,000만 행에서 캐시는 인덱스 없는 반복 조회를 인덱스 있는
조회만큼 싸게 만들었습니다(아래).

**`FINAL` 아래의 skip index.** 24.8 · 25.3은 기본으로 `FINAL`에서 인덱스를 쓰지 않고(1,210,112행), 25.8부터 씁니다
(171,072행). `EXPLAIN`에 `PrimaryKeyExpand` 단계가 붙습니다(granule 5 → 14, 다른 파트의 같은 키 범위). 답은 모든 빌드에서
맞습니다. `use_skip_indexes_if_final = 0`이면 ≤26.3은 매트릭스 두 번 모두 1,210,112행을 읽었고, 26.8 · 26.10은 더 적게,
두 번이 서로 다르게 읽었습니다(1,137,344–1,191,920). 캐시 때문은 아니고(26.10에서 캐시를 끄고 손으로 확인), 더 조사하지
않았습니다.

### 2,000만 행 조회(`07-scale.sql`)

5회 최솟값 ms(`results/*.json`의 `durations_ms`), `use_query_condition_cache = 0`(24.8은 캐시가 없어 설정 없는 실행).
모든 컬럼 `CODEC(LZ4)`.

| 쿼리 | 24.8 | 25.3 | 25.8 | 26.3 | 26.8 | 26.10 | 26.10, 테이블 기본 LZ4 |
|---|---|---|---|---|---|---|---|
| 기본 키 `id = …` | 1 | 1 | 1 | 2 | 1 | 1 | |
| `bloom_filter` `uid = …`(475,136행) | 4 | 5 | 4 | 5 | 5 | 18 | 5 |
| 같은 쿼리, `use_skip_indexes = 0`(2,000만 행) | 5 | 7 | 6 | 5 | 6 | 5 | |
| `tokenbf_v1` `hasToken`(163,840행) | 38 | 40 | 38 | 35 | 37 | 67 | 37 |
| 같은 쿼리, `use_skip_indexes = 0` | 45 | 43 | 32 | 29 | 25 | 23 | |
| 키가 아닌 컬럼, 인덱스 없음 | 4 | 4 | 4 | 4 | 4 | 4 | |

- 26.10의 인덱스 조회가 느린 것은 인덱스 파일 코덱 때문입니다. 파트 기본값이 `ZSTD(3)`이라(`07-codec`) `tokenbf` 인덱스가
  62.9 MiB 대신 40.6 MiB이고 읽기가 느립니다. 테이블의 `default_compression_codec = 'LZ4'`를 고정하면(`big_lz4`, 이 테이블
  설정은 25.8 빌드부터 있음) 37 ms와 5 ms입니다.
- 64비트 해시 컬럼의 `bloom_filter`는 여기서 이득이 없었습니다(있으면 4–5 ms, 없으면 5–7 ms). 문자열 컬럼의 `tokenbf`는
  25.8–26.10에서 스캔보다 느렸습니다(35–38 ms 대 23–32 ms). 필터 63 MiB를 읽는 비용이 피하는 스캔보다 컸습니다.
  `text` 인덱스(`03-text.sql`)는 같은 조회를 1–2 ms에 답했습니다.
- 캐시를 켜면(25.8부터 기본) 인덱스 없는 반복 조회가 1–3 ms였습니다(65,536 / 327,680행).

### 화면

2026-11-05에 이 실습의 파일을 넣은 로컬 일회용 컨테이너의 ClickHouse `/play` UI에서 노트 글
`core-architecture/clickhouse-index`용으로 찍었습니다.

- [`images/01-explain-generic-exclusion-26-10.png`](images/01-explain-generic-exclusion-26-10.png) — 26.10.3.7, 값 10개인 `a`의 `ORDER BY (a, b)`에서 `b = 5000003`: granule 19/1000, generic exclusion search
- [`images/02-or-skip-indexes-25-8.png`](images/02-or-skip-indexes-25-8.png) — 25.8.33.6, `uid = … OR cat = 'rare'`: `i_uid`만 분석, 1000/1000
- [`images/03-or-skip-indexes-26-10.png`](images/03-or-skip-indexes-26-10.png) — 같은 쿼리, 26.10.3.7: `<Combined skip indexes>` 28/1000
- [`images/04-statistics-part-pruning-26-10.png`](images/04-statistics-part-pruning-26-10.png) — 26.10.3.7, `many = 100001`(컬럼 범위 밖): 기본 키와 `set(100)` 인덱스 앞의 `Statistics` 0/1000
- [`images/05-text-index-size-26-10.png`](images/05-text-index-size-26-10.png) — 26.10.3.7, 2,000만 행의 `text` 인덱스: 232.89 MiB(기본), 97.24 MiB(`bitpacking`), 40.00 MiB(`pfor`), 데이터 파트 225.41 MiB
- [`images/06-condition-cache-26-10.png`](images/06-condition-cache-26-10.png) — 26.10.3.7, `count() WHERE v = 7`을 두 번, 캐시를 끄고 한 번 돌린 `system.query_log`: 8,192,000 / 262,144 / 8,192,000행

### 여기서 확인하지 않은 것

- Distributed · 복제 테이블, `SharedMergeTree`, parallel replicas, ClickHouse Cloud.
- Projection, `vector_similarity` 인덱스, 쿼리 계획 입력으로서의 컬럼 통계(파트 제외만 드러남), `splitByNonAlpha` 외의
  토크나이저(`usecase/fulltext-search`, `usecase/korean-rag-tokenizers` 참고), phrase search, 2,000만 행보다 큰 데이터,
  파트가 많은 테이블.

Verified on 24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3 and 26.10.3.7, 2026-11-05 (`./run_matrix.py`, all six; `tools/hol run` on 26.10.3.7).
