# Distinct-count state size in materialized-view rollups

[English](#english) | [한국어](#한국어)

---

## English

A per-minute rollup fed by a materialized view into an `AggregatingMergeTree` usually holds a few sums and
one distinct count (`uniqState`). This lab measures how much of such a rollup that one column takes, whether a
narrower input type (`UInt32` instead of `UInt64` or `String`) makes it smaller, what `uniqCombined`,
`uniqCombined(12)`, `uniqHLL12` and `uniqExact` cost and how far off they are, how a 10-minute rollup fed
**from the 1-minute rollup** (cascading materialized view) compares, and what each choice does to a Top 10 /
Bottom 10 query over the last hour. Synthetic data on one local container; nothing here comes from a
production system.

Cascading materialized views with TTL for retention are in [workload/cascading-mv-ttl](../cascading-mv-ttl/);
this lab does not repeat that.

### Run it

```bash
cd workload/mv-uniq-state-size
./run.sh                                        # fresh container, every NN-*.sql, 06-topn.sql five times
                                                # -> results/<version>.txt; about 2.5 minutes (2026-11-05, 12 CPUs)
KEEP=1 ./run.sh                                 # leave the container (musz-<tag>) running afterwards
tools/hol run workload/mv-uniq-state-size       # from the repository root: every file once, must not raise
```

`run.sh` needs only Docker. It takes the image tag from `lab.yaml`, starts the container the way `tools/hol up`
does (no published ports), writes the date, `version()`, host CPU, Docker VM size and the CPU% of every other
running container at the start and before the timing runs into the results file, runs each file with
`clickhouse-client --echo`, and removes the container (and its volume) at the end. `99-cleanup.sql` is skipped
by `run.sh` and run by `tools/hol`.

### Files

| File | What it does |
|---|---|
| `01-setup.sql` | `events` (raw page views), `rollup_1m` (`AggregatingMergeTree`, key `(bucket, kind, page)`) with the same distinct-user count nine times: `uniq` over `String`, `UInt64` and `UInt32`, `uniqCombined`, `uniqCombined(12)`, `uniqHLL12`, `uniqExact` over `String`, `UInt64` and `UInt32`; `mv_1m` from `events`; `rollup_10m` with the same columns and `mv_10m` **from `rollup_1m`** with `-MergeState`. Every column is `CODEC(LZ4)`, rollups use `min_bytes_for_wide_part = 0` (per-column sizes) |
| `02-load.sql` | 36,000,000 rows, 2026-11-01 00:00–02:59 UTC, 200,000 per minute, 12 INSERTs of 15 minutes; 500,000 users, each fixed to one of 2,000 pages with a skewed distribution; then `OPTIMIZE … FINAL` on all three tables |
| `03-state-size.sql` | serialized state bytes (`length(CAST(state AS String))`) by distinct values per group (1 to 1,000,000) for each function; the same for `String`, `Nullable(String)`, `UInt64`, `UInt32` input; relative error at 10 to 1,000,000 distinct values (10 groups each, `uniqExact` as the control) |
| `04-rollup-size.sql` | rows and bytes per table, distinct users per group, declared codecs, bytes per column from `system.parts_columns`, each distinct-count column's share of a rollup that holds only it, 10-minute against 1-minute bytes per column |
| `05-cascade-check.sql` | the cascaded 10-minute rollup against 10-minute groups computed from the raw rows (positive check), the sum of per-minute distinct counts against the true 10-minute count (negative control), and the direct computation repeated five times to see which functions give the same answer every time |
| `06-topn.sql` | Top 10 and Bottom 10 pages by distinct users over the last hour, the same query on each state column, on the 10-minute rollup and on the raw rows (`FORMAT Null`, tagged with `log_comment`) |
| `07-topn-accuracy.sql` | the exact Top 10 / Bottom 10; per state column the relative error per page and whether it returns the same Top 10 / Bottom 10 pages in the same order; error per rollup row |
| `08-timing.sql` | `06-topn.sql` runs from `system.query_log`: median and minimum time, rows and bytes read, peak memory |
| `99-cleanup.sql` | drops the `mv_uniq` database |

### Results

Verified on ClickHouse 26.10.3.7 (`clickhouse/clickhouse-server:26.10.3.7`), 2026-11-05, Apple M4 Pro host,
Docker Desktop VM with 12 CPUs and 15.6 GiB, 36,000,000 raw rows. Other containers were running at the same
time; their CPU% is in the results file. The full output is [results/26.10.3.7.txt](results/26.10.3.7.txt);
every number below is copied from it. Sizes are of fully merged parts (one part per table after
`OPTIMIZE … FINAL`), all columns `CODEC(LZ4)`.

**One state, by distinct values per group** (`03-state-size.sql`, bytes, input `UInt64`):

| distinct values | `uniq` | `uniqCombined` | `uniqCombined(12)` | `uniqHLL12` | `uniqExact` |
|---:|---:|---:|---:|---:|---:|
| 1 | 7 | 6 | 6 | 10 | 9 |
| 10 | 43 | 42 | 42 | 82 | 81 |
| 30 | 123 | 122 | 122 | 2,651 | 241 |
| 100 | 403 | 402 | 402 | 2,651 | 801 |
| 300 | 1,204 | 1,203 | 2,651 | 2,651 | 2,402 |
| 600 | 2,404 | 2,403 | 2,651 | 2,651 | 4,802 |
| 700 | 2,804 | 2,803 | 2,651 | 2,651 | 5,602 |
| 1,000 | 4,004 | 4,003 | 2,651 | 2,651 | 8,002 |
| 10,000 | 40,004 | 81,993 | 2,651 | 2,651 | 80,002 |
| 100,000 | 199,815 | 81,993 | 2,651 | 2,651 | 800,003 |
| 1,000,000 | 251,151 | 81,993 | 2,651 | 2,651 | 8,000,003 |

**The same values as another type** (bytes at 1,000 distinct values; 100 and 10,000 are in the results file):

| function | `String` (32 hex) | `Nullable(String)` | `UInt64` | `UInt32` |
|---|---:|---:|---:|---:|
| `uniq` | 4,004 | 4,005 | 4,004 | 4,004 |
| `uniqCombined` | 8,003 | 8,004 | 4,003 | 4,003 |
| `uniqCombined(12)` | 3,291 | 3,292 | 2,651 | 2,651 |
| `uniqHLL12` | 2,651 | 2,652 | 2,651 | 2,651 |
| `uniqExact` | 16,002 | 16,003 | 8,002 | 4,002 |

**Relative error** (`03-state-size.sql`, 10 groups per count, mean / max %):

| distinct values | `uniq` | `uniqCombined` | `uniqCombined(12)` | `uniqHLL12` |
|---:|---|---|---|---|
| 100 | 0 / 0 | 0 / 0 | 0 / 0 | 0.80 / 2.0 |
| 1,000 | 0 / 0 | 0 / 0 | 1.04 / 1.7 | 1.03 / 2.3 |
| 10,000 | 0 / 0 | 0.14 / 0.43 | 2.29 / 3.9 | 3.17 / 5.12 |
| 100,000 | 0.17 / 0.34 | 0.17 / 0.68 | 1.70 / 4.69 | 0.97 / 2.71 |
| 1,000,000 | 0.27 / 0.49 | 0.18 / 0.45 | 1.12 / 3.37 | 1.25 / 3.61 |

`uniqExact`, the control, is 0 everywhere.

**The rollups** (`04-rollup-size.sql`). Distinct users per group: 1-minute p50 11, p90 44, p99 174, max
5,273 (1,436,078 groups); 10-minute p50 80, p90 225, p99 883, max 21,959 (144,000 groups). Bytes per column, compressed
(LZ4); share = this column / (this column + the five other columns: `bucket`, `kind`, `page`, `events`,
`latency_sum`, together 13.11 MiB in the 1-minute rollup and 1.41 MiB in the 10-minute rollup):

| column | 1-minute | bytes/row (uncompressed) | share | 10-minute | share | 10-minute / 1-minute |
|---|---:|---:|---:|---:|---:|---:|
| `uniq(String)` | 131.22 MiB | 95.4 | 90.9% | 73.50 MiB | 98.1% | 0.56 |
| `uniq(UInt64)` | 131.22 MiB | 95.4 | 90.9% | 73.50 MiB | 98.1% | 0.56 |
| `uniq(UInt32)` | 131.22 MiB | 95.4 | 90.9% | 73.50 MiB | 98.1% | 0.56 |
| `uniqCombined(UInt64)` | 129.84 MiB | 94.4 | 90.8% | 72.21 MiB | 98.1% | 0.556 |
| `uniqCombined(12)(UInt64)` | 120.10 MiB | 95.0 | 90.2% | 57.32 MiB | 97.6% | 0.477 |
| `uniqHLL12(UInt64)` | 173.57 MiB | 1,022.6 | 93.0% | 61.56 MiB | 97.8% | 0.355 |
| `uniqExact(String)` | 509.68 MiB | 370.7 | 97.5% | 292.38 MiB | 99.5% | 0.574 |
| `uniqExact(UInt64)` | 255.54 MiB | 185.9 | 95.1% | 146.28 MiB | 99.0% | 0.572 |
| `uniqExact(UInt32)` | 128.47 MiB | 93.4 | 90.7% | 73.23 MiB | 98.1% | 0.57 |

The 10-minute rollup has 0.1 of the rows (144,000 against 1,436,078); `bucket`, `page`, `events` and
`latency_sum` shrink to 0.10–0.11. `uniqHLL12` is the only state that compresses (1.37 GiB uncompressed in
the 1-minute rollup, ratio 8.07).

On this build the `uniq` columns are stored as `AggregateFunction(1, uniq, …)`, a state version, although
`01-setup.sql` declares `AggregateFunction(uniq, …)`; the other functions have none. The built-in description of
`uniq` (`system.functions`, read 2026-11-05) says servers from 26.8 also keep a small sample of 64-bit hashes and
that states written by older servers carry none.

**The cascade** (`05-cascade-check.sql`). The 10-minute rollup fed from the 1-minute rollup against 10-minute
groups computed from the raw rows: 144,000 groups on both sides, 0 differences in `events`, `uniqExact`,
`uniq`, `uniqCombined` and `uniqHLL12`; `uniqCombined(12)` differs in 20 groups, every one of them with exactly
256 true distinct values, by at most 10. The negative control, adding up the per-minute distinct counts, is wrong
in 143,945 of 144,000 groups and 1.53 times the true count on average.

The same direct 10-minute computation repeated: `uniq`, `uniqCombined` and `uniqHLL12` gave the same result
fingerprint in all five runs; `uniqCombined(12)` gave three different fingerprints in the three runs with the
default `max_threads` and the same one in the two runs with `max_threads = 1`. So the 20 is not a cascade error:
`uniqCombined(12)` itself returns different answers for the same data, at its switch point. The built-in
description says `uniqCombined` "provides the result deterministically (it does not depend on the query
processing order)".

**Error inside the rollups** (`07-topn-accuracy.sql` (c), per rollup row against `uniqExact`, mean / p99 / max %,
share of groups not exact):

| | `uniq` | `uniqCombined` | `uniqCombined(12)` | `uniqHLL12` |
|---|---|---|---|---|
| 1-minute groups | 0 / 0 / 0, 0% | 0 / 0 / 0, 0% | 0.005 / 0 / 5.76, 0.49% | 0.165 / 3.70 / 15.0, 7.62% |
| 10-minute groups | 0 / 0 / 0, 0% | 0 / 0 / 0.45, 0.02% | 0.076 / 1.81 / 4.51, 7.47% | 0.764 / 3.70 / 11.5, 54.29% |

**Top 10 / Bottom 10 over the last hour** (`07-topn-accuracy.sql` (b), 2,000 pages from the 1-minute rollup). The
exact Top 10 runs from 24,016 to 2,482 users, the exact Bottom 10 from 81 to 86. Every state column returned the
same ten pages for both lists; the order was the same everywhere except the `uniqHLL12` Bottom 10. Error per
page, mean / max %: `uniq` (all three types), `uniqExact(String)`, `uniqExact(UInt32)` 0 / 0; `uniqCombined`
0 / 0.237; `uniqCombined(12)` 0.199 / 3.838; `uniqHLL12` 0.887 / 4.902.

**Time** (`08-timing.sql`, five runs, warm). `read from disk` is `ProfileEvents['ReadCompressedBytes']`;
`query_log.read_bytes` is the in-memory size of the columns read and is in the results file.

| source | median ms | min ms | rows read | read from disk | decompressed | peak memory |
|---|---:|---:|---:|---:|---:|---:|
| 1-minute `uniq(String)` | 72 | 58 | 485,806 | 45.91 MiB | 51.61 MiB | 63.01 MiB |
| 1-minute `uniq(UInt64)` | 59 | 57 | 485,806 | 45.91 MiB | 51.60 MiB | 62.94 MiB |
| 1-minute `uniq(UInt32)` | 60 | 58 | 485,806 | 45.91 MiB | 51.60 MiB | 63.00 MiB |
| 1-minute `uniqCombined` | 56 | 52 | 485,806 | 45.44 MiB | 51.14 MiB | 69.74 MiB |
| 1-minute `uniqCombined(12)` | 49 | 44 | 485,806 | 42.14 MiB | 51.42 MiB | 60.04 MiB |
| 1-minute `uniqHLL12` | 130 | 113 | 485,806 | 60.23 MiB | 480.46 MiB | 108.85 MiB |
| 1-minute `uniqExact(String)` | 91 | 84 | 485,806 | 173.84 MiB | 179.03 MiB | 228.21 MiB |
| 1-minute `uniqExact(UInt64)` | 59 | 52 | 485,806 | 87.93 MiB | 93.46 MiB | 151.69 MiB |
| 1-minute `uniqExact(UInt32)` | 50 | 41 | 485,806 | 44.98 MiB | 50.67 MiB | 87.67 MiB |
| 10-minute `uniq(UInt64)` | 38 | 38 | 48,060 | 24.83 MiB | 25.92 MiB | 55.77 MiB |
| 10-minute `uniqExact(UInt64)` | 34 | 29 | 48,060 | 49.62 MiB | 50.61 MiB | 111.34 MiB |
| raw `uniq(UInt64)` | 48 | 44 | 12,005,632 | 124.97 MiB | 184.63 MiB | 61.62 MiB |
| raw `uniqExact(UInt64)` | 50 | 47 | 12,005,632 | 124.93 MiB | 184.50 MiB | 157.16 MiB |

### What the numbers say

- One distinct-count column is about 91% of a 1-minute rollup and 98% of a 10-minute one here, whichever
  function it uses. The other columns are 13.11 MiB against 131.22 MiB for `uniq`.
- A narrower input type does not shrink `uniq` (4 bytes per distinct value for `String`, `UInt64` and `UInt32`;
  `Nullable` adds one byte per state). It shrinks `uniqExact` (16 / 8 / 4 bytes per value) and the small-set
  form of `uniqCombined` over `String` (twice the integer size).
- The fixed-size states (`uniqCombined(12)` and `uniqHLL12`, 2,651 bytes) are smaller than `uniq` only above
  600–700 distinct values per group. With a median of 11 per 1-minute group, `uniqCombined(12)` saved 8% and
  `uniqHLL12` cost 32% more (and was the slowest to query: 480 MiB to decompress).
- A 10-minute rollup does not cost a tenth: the state columns were 0.56 of the 1-minute ones while the rows
  were 0.1. A 1-minute rollup without the distinct count is 13.11 MiB.
- The cascade is correct for `uniqExact`, `uniq`, `uniqCombined` and `uniqHLL12`. Check it with a query like the
  one in `05-cascade-check.sql` and its negative control.
- At 12 million raw rows per hour on 12 CPUs, the raw table answered the last-hour Top/Bottom 10 as fast as the
  1-minute rollup (48–50 ms against 49–72 ms for the `uniq`-sized states) while reading 2.7 times the bytes;
  the 10-minute rollup took 34–38 ms. This lab does not measure how the gap grows with the raw volume.

### Limits

One build, one machine, synthetic data: users uniform over 500,000, each fixed to one page, so the distinct
count per group follows the page skew and not a real workload. Sizes are after `OPTIMIZE … FINAL`; a live rollup
also holds unmerged partial states. Timings are warm (median of five) with other containers running. The
`uniqCombined(12)` difference count changes from run to run (see above).

---

## 한국어

materialized view로 `AggregatingMergeTree`에 쌓는 1분 롤업에는 보통 합계 몇 개와 고유 수(`uniqState`) 하나가
들어갑니다. 이 실습은 그 고유 수 컬럼 하나가 롤업의 얼마를 차지하는지, 입력 타입을 좁히면(`UInt64`나
`String` 대신 `UInt32`) 작아지는지, `uniqCombined` · `uniqCombined(12)` · `uniqHLL12` · `uniqExact`의 크기와
오차, **1분 롤업에서 이어 만든** 10분 롤업(cascading materialized view)의 크기와 정확성, 그리고 각 선택이
최근 1시간 Top 10 / Bottom 10 조회에 주는 영향을 잽니다. 로컬 컨테이너 하나와 합성 데이터만 씁니다.
운영 시스템의 데이터는 없습니다.

TTL로 보관 기간을 관리하는 cascading materialized view는 [workload/cascading-mv-ttl](../cascading-mv-ttl/)에
있고, 여기서 반복하지 않습니다.

### 실행

```bash
cd workload/mv-uniq-state-size
./run.sh                                        # 새 컨테이너, NN-*.sql 전부, 06-topn.sql은 다섯 번
                                                # -> results/<버전>.txt, 약 2.5분(2026-11-05, 12 CPU)
KEEP=1 ./run.sh                                 # 끝난 뒤 컨테이너(musz-<태그>)를 남김
tools/hol run workload/mv-uniq-state-size       # 저장소 루트에서: 파일마다 한 번, 예외가 없어야 함
```

`run.sh`는 Docker만 있으면 됩니다. 이미지 태그는 `lab.yaml`(`clickhouse:`)에서 읽고, `tools/hol up`과 같은
방식으로(포트 공개 없이) 컨테이너를 띄웁니다. 결과 파일에 날짜, `version()`, 호스트 CPU, Docker VM 크기,
시작할 때와 시간 측정 직전에 돌던 다른 컨테이너의 CPU%를 적고, 파일마다 `clickhouse-client --echo`로
실행한 뒤 컨테이너를 볼륨째 지웁니다. `99-cleanup.sql`은 `run.sh`가 건너뛰고 `tools/hol`이 실행합니다.

### 파일

| 파일 | 하는 일 |
|---|---|
| `01-setup.sql` | `events`(원본 페이지 조회), `rollup_1m`(`AggregatingMergeTree`, 키 `(bucket, kind, page)`)에 같은 고유 사용자 수를 아홉 번: `String` · `UInt64` · `UInt32` 입력의 `uniq`, `uniqCombined`, `uniqCombined(12)`, `uniqHLL12`, `String` · `UInt64` · `UInt32` 입력의 `uniqExact`. `events`에서 받는 `mv_1m`, 같은 컬럼의 `rollup_10m`과 **`rollup_1m`에서** `-MergeState`로 받는 `mv_10m`. 모든 컬럼 `CODEC(LZ4)`, 롤업은 `min_bytes_for_wide_part = 0`(컬럼별 크기) |
| `02-load.sql` | 3,600만 행, 2026-11-01 00:00–02:59 UTC, 분당 20만 행, 15분씩 INSERT 12번. 사용자 50만 명이 2,000개 페이지 중 하나에 고정(치우친 분포). 끝에 세 테이블 `OPTIMIZE … FINAL` |
| `03-state-size.sql` | 그룹당 고유값(1–1,000,000)별 직렬화한 상태 크기(`length(CAST(state AS String))`), `String` · `Nullable(String)` · `UInt64` · `UInt32` 입력별 크기, 고유값 10–1,000,000에서 상대 오차(값마다 그룹 10개, 대조군 `uniqExact`) |
| `04-rollup-size.sql` | 테이블별 행과 바이트, 그룹당 고유 사용자, 선언된 코덱, 상태 컬럼 타입, `system.parts_columns`의 컬럼별 바이트, 고유 수 컬럼 하나만 둔 롤업에서의 비중, 컬럼별 10분 대 1분 바이트 |
| `05-cascade-check.sql` | cascade로 만든 10분 롤업과 원본에서 바로 계산한 10분 그룹 비교(양성 검사), 분당 고유 수의 합과 실제 10분 고유 수 비교(음성 대조), 직접 계산을 다섯 번 반복해 함수마다 답이 매번 같은지 |
| `06-topn.sql` | 최근 1시간 고유 사용자 기준 Top 10 · Bottom 10 페이지. 상태 컬럼마다, 10분 롤업, 원본에서 같은 쿼리(`FORMAT Null`, `log_comment`로 표시) |
| `07-topn-accuracy.sql` | 정확한 Top 10 · Bottom 10, 상태 컬럼별 페이지 오차와 같은 페이지 · 같은 순서인지, 롤업 행별 오차 |
| `08-timing.sql` | `system.query_log`의 `06-topn.sql` 실행: 중앙값 · 최솟값 시간, 읽은 행과 바이트, 최대 메모리 |
| `99-cleanup.sql` | `mv_uniq` 데이터베이스 삭제 |

### 결과

ClickHouse 26.10.3.7(`clickhouse/clickhouse-server:26.10.3.7`)에서 검증했습니다. 2026-11-05, Apple M4 Pro
호스트, Docker Desktop VM 12 CPU · 15.6 GiB, 원본 3,600만 행. 같은 시간에 다른 컨테이너가 돌고 있었고 그
CPU%는 결과 파일에 있습니다. 전체 출력은 [results/26.10.3.7.txt](results/26.10.3.7.txt)이고 아래 숫자는 모두
거기서 옮겼습니다. 크기는 `OPTIMIZE … FINAL` 뒤 테이블마다 파트 하나로 병합된 상태이고, 모든 컬럼이
`CODEC(LZ4)`입니다.

**상태 하나의 크기, 그룹당 고유값별**(`03-state-size.sql`, 바이트, 입력 `UInt64`):

| 고유값 | `uniq` | `uniqCombined` | `uniqCombined(12)` | `uniqHLL12` | `uniqExact` |
|---:|---:|---:|---:|---:|---:|
| 1 | 7 | 6 | 6 | 10 | 9 |
| 10 | 43 | 42 | 42 | 82 | 81 |
| 30 | 123 | 122 | 122 | 2,651 | 241 |
| 100 | 403 | 402 | 402 | 2,651 | 801 |
| 300 | 1,204 | 1,203 | 2,651 | 2,651 | 2,402 |
| 600 | 2,404 | 2,403 | 2,651 | 2,651 | 4,802 |
| 700 | 2,804 | 2,803 | 2,651 | 2,651 | 5,602 |
| 1,000 | 4,004 | 4,003 | 2,651 | 2,651 | 8,002 |
| 10,000 | 40,004 | 81,993 | 2,651 | 2,651 | 80,002 |
| 100,000 | 199,815 | 81,993 | 2,651 | 2,651 | 800,003 |
| 1,000,000 | 251,151 | 81,993 | 2,651 | 2,651 | 8,000,003 |

**같은 값을 다른 타입으로**(고유값 1,000일 때 바이트, 100과 10,000은 결과 파일):

| 함수 | `String`(16진 32자) | `Nullable(String)` | `UInt64` | `UInt32` |
|---|---:|---:|---:|---:|
| `uniq` | 4,004 | 4,005 | 4,004 | 4,004 |
| `uniqCombined` | 8,003 | 8,004 | 4,003 | 4,003 |
| `uniqCombined(12)` | 3,291 | 3,292 | 2,651 | 2,651 |
| `uniqHLL12` | 2,651 | 2,652 | 2,651 | 2,651 |
| `uniqExact` | 16,002 | 16,003 | 8,002 | 4,002 |

**상대 오차**(`03-state-size.sql`, 값마다 그룹 10개, 평균 / 최대 %):

| 고유값 | `uniq` | `uniqCombined` | `uniqCombined(12)` | `uniqHLL12` |
|---:|---|---|---|---|
| 100 | 0 / 0 | 0 / 0 | 0 / 0 | 0.80 / 2.0 |
| 1,000 | 0 / 0 | 0 / 0 | 1.04 / 1.7 | 1.03 / 2.3 |
| 10,000 | 0 / 0 | 0.14 / 0.43 | 2.29 / 3.9 | 3.17 / 5.12 |
| 100,000 | 0.17 / 0.34 | 0.17 / 0.68 | 1.70 / 4.69 | 0.97 / 2.71 |
| 1,000,000 | 0.27 / 0.49 | 0.18 / 0.45 | 1.12 / 3.37 | 1.25 / 3.61 |

대조군 `uniqExact`는 모두 0입니다.

**롤업**(`04-rollup-size.sql`). 그룹당 고유 사용자: 1분 p50 11, p90 44, p99 174, 최대 5,273(그룹
1,436,078개), 10분 p50 80, p90 225, p99 883, 최대 21,959(그룹 144,000개). 컬럼별 압축 크기(LZ4). 비중 =
이 컬럼 / (이 컬럼 + 나머지 다섯 컬럼 `bucket` · `kind` · `page` · `events` · `latency_sum`, 1분 롤업에서
합 13.11 MiB, 10분 롤업에서 1.41 MiB):

| 컬럼 | 1분 | 행당 바이트(비압축) | 비중 | 10분 | 비중 | 10분 / 1분 |
|---|---:|---:|---:|---:|---:|---:|
| `uniq(String)` | 131.22 MiB | 95.4 | 90.9% | 73.50 MiB | 98.1% | 0.56 |
| `uniq(UInt64)` | 131.22 MiB | 95.4 | 90.9% | 73.50 MiB | 98.1% | 0.56 |
| `uniq(UInt32)` | 131.22 MiB | 95.4 | 90.9% | 73.50 MiB | 98.1% | 0.56 |
| `uniqCombined(UInt64)` | 129.84 MiB | 94.4 | 90.8% | 72.21 MiB | 98.1% | 0.556 |
| `uniqCombined(12)(UInt64)` | 120.10 MiB | 95.0 | 90.2% | 57.32 MiB | 97.6% | 0.477 |
| `uniqHLL12(UInt64)` | 173.57 MiB | 1,022.6 | 93.0% | 61.56 MiB | 97.8% | 0.355 |
| `uniqExact(String)` | 509.68 MiB | 370.7 | 97.5% | 292.38 MiB | 99.5% | 0.574 |
| `uniqExact(UInt64)` | 255.54 MiB | 185.9 | 95.1% | 146.28 MiB | 99.0% | 0.572 |
| `uniqExact(UInt32)` | 128.47 MiB | 93.4 | 90.7% | 73.23 MiB | 98.1% | 0.57 |

10분 롤업의 행은 1분의 0.1배(144,000 대 1,436,078)이고, `bucket` · `page` · `events` · `latency_sum`은
0.10–0.11배로 줄었습니다. 압축되는 상태는 `uniqHLL12`뿐입니다(1분 롤업에서 비압축 1.37 GiB, 압축률 8.07).

이 빌드는 `uniq` 컬럼을 `AggregateFunction(1, uniq, …)`, 즉 상태 버전을 붙여 저장합니다. `01-setup.sql`은
`AggregateFunction(uniq, …)`로 선언했고, 다른 함수에는 버전이 붙지 않습니다. `uniq`의 내장 설명
(`system.functions`, 2026-11-05에 읽음)에 따르면 26.8부터 서버가 64비트 해시의 작은 표본도 함께 두고,
그보다 오래된 서버가 쓴 상태에는 그 표본이 없습니다.

**cascade**(`05-cascade-check.sql`). 1분 롤업에서 받은 10분 롤업과 원본에서 바로 계산한 10분 그룹: 양쪽
모두 그룹 144,000개, `events` · `uniqExact` · `uniq` · `uniqCombined` · `uniqHLL12` 차이 0.
`uniqCombined(12)`는 20개 그룹에서 달랐고, 모두 실제 고유값이 정확히 256인 그룹이었으며 차이는 최대
10이었습니다. 음성 대조(분당 고유 수를 더하기)는 144,000개 중 143,945개 그룹에서 틀렸고 평균 실제 값의
1.53배였습니다.

같은 직접 계산을 반복하면 `uniq` · `uniqCombined` · `uniqHLL12`는 다섯 번 모두 같은 결과 지문을 냈고,
`uniqCombined(12)`는 기본 `max_threads`로 세 번 돌린 결과가 셋 다 달랐으며 `max_threads = 1`로 두 번 돌린
결과는 같았습니다. 그러니 20개는 cascade의 오류가 아니라, `uniqCombined(12)`가 전환 지점에서 같은 데이터에
다른 답을 내는 것입니다. 내장 설명은 `uniqCombined`가 "provides the result deterministically (it does not
depend on the query processing order)"라고 적고 있습니다.

**롤업 안의 오차**(`07-topn-accuracy.sql` (c), 롤업 행마다 `uniqExact`와 비교, 평균 / p99 / 최대 %, 정확하지
않은 그룹의 비율):

| | `uniq` | `uniqCombined` | `uniqCombined(12)` | `uniqHLL12` |
|---|---|---|---|---|
| 1분 그룹 | 0 / 0 / 0, 0% | 0 / 0 / 0, 0% | 0.005 / 0 / 5.76, 0.49% | 0.165 / 3.70 / 15.0, 7.62% |
| 10분 그룹 | 0 / 0 / 0, 0% | 0 / 0 / 0.45, 0.02% | 0.076 / 1.81 / 4.51, 7.47% | 0.764 / 3.70 / 11.5, 54.29% |

**최근 1시간 Top 10 / Bottom 10**(`07-topn-accuracy.sql` (b), 1분 롤업, 페이지 2,000개). 정확한 Top 10은 사용자
24,016명에서 2,482명, Bottom 10은 81명에서 86명입니다. 모든 상태 컬럼이 두 목록 모두 같은 열 개 페이지를
돌려줬고, 순서는 `uniqHLL12`의 Bottom 10만 달랐습니다. 페이지별 오차(평균 / 최대 %): `uniq`(세 타입 모두),
`uniqExact(String)`, `uniqExact(UInt32)` 0 / 0, `uniqCombined` 0 / 0.237, `uniqCombined(12)` 0.199 / 3.838,
`uniqHLL12` 0.887 / 4.902.

**시간**(`08-timing.sql`, 다섯 번, 캐시가 데워진 상태). `디스크에서 읽음`은
`ProfileEvents['ReadCompressedBytes']`입니다. `query_log.read_bytes`는 읽은 컬럼의 메모리 크기라 상태
컬럼에서는 디스크 크기와 다르고, 결과 파일에 있습니다.

| 원천 | 중앙값 ms | 최솟값 ms | 읽은 행 | 디스크에서 읽음 | 압축 해제 | 최대 메모리 |
|---|---:|---:|---:|---:|---:|---:|
| 1분 `uniq(String)` | 72 | 58 | 485,806 | 45.91 MiB | 51.61 MiB | 63.01 MiB |
| 1분 `uniq(UInt64)` | 59 | 57 | 485,806 | 45.91 MiB | 51.60 MiB | 62.94 MiB |
| 1분 `uniq(UInt32)` | 60 | 58 | 485,806 | 45.91 MiB | 51.60 MiB | 63.00 MiB |
| 1분 `uniqCombined` | 56 | 52 | 485,806 | 45.44 MiB | 51.14 MiB | 69.74 MiB |
| 1분 `uniqCombined(12)` | 49 | 44 | 485,806 | 42.14 MiB | 51.42 MiB | 60.04 MiB |
| 1분 `uniqHLL12` | 130 | 113 | 485,806 | 60.23 MiB | 480.46 MiB | 108.85 MiB |
| 1분 `uniqExact(String)` | 91 | 84 | 485,806 | 173.84 MiB | 179.03 MiB | 228.21 MiB |
| 1분 `uniqExact(UInt64)` | 59 | 52 | 485,806 | 87.93 MiB | 93.46 MiB | 151.69 MiB |
| 1분 `uniqExact(UInt32)` | 50 | 41 | 485,806 | 44.98 MiB | 50.67 MiB | 87.67 MiB |
| 10분 `uniq(UInt64)` | 38 | 38 | 48,060 | 24.83 MiB | 25.92 MiB | 55.77 MiB |
| 10분 `uniqExact(UInt64)` | 34 | 29 | 48,060 | 49.62 MiB | 50.61 MiB | 111.34 MiB |
| 원본 `uniq(UInt64)` | 48 | 44 | 12,005,632 | 124.97 MiB | 184.63 MiB | 61.62 MiB |
| 원본 `uniqExact(UInt64)` | 50 | 47 | 12,005,632 | 124.93 MiB | 184.50 MiB | 157.16 MiB |

### 숫자가 말하는 것

- 여기서 고유 수 컬럼 하나는 어떤 함수를 쓰든 1분 롤업의 약 91%, 10분 롤업의 98%였습니다. 나머지 컬럼은
  13.11 MiB, `uniq`는 131.22 MiB입니다.
- 입력 타입을 좁혀도 `uniq`는 줄지 않습니다(`String` · `UInt64` · `UInt32` 모두 고유값당 4바이트,
  `Nullable`은 상태당 1바이트 추가). 줄어드는 것은 `uniqExact`(값당 16 / 8 / 4바이트)와 `String` 입력
  `uniqCombined`의 작은 집합 형태(정수의 두 배)입니다.
- 고정 크기 상태(`uniqCombined(12)`, `uniqHLL12`, 2,651바이트)는 그룹당 고유값이 600–700을 넘어야 `uniq`보다
  작습니다. 1분 그룹 중앙값이 11인 이 데이터에서 `uniqCombined(12)`는 8% 줄었고 `uniqHLL12`는 32% 커졌습니다
  (조회도 가장 느렸습니다. 압축 해제 480 MiB).
- 10분 롤업은 1/10이 아닙니다. 행은 0.1배인데 상태 컬럼은 0.56배였습니다. 고유 수가 없는 1분 롤업은
  13.11 MiB입니다.
- cascade는 `uniqExact` · `uniq` · `uniqCombined` · `uniqHLL12`에서 정확했습니다. `05-cascade-check.sql` 같은
  쿼리와 음성 대조로 확인합니다.
- 12 CPU에서 시간당 원본 1,200만 행이면, 최근 1시간 Top/Bottom 10을 원본 테이블이 1분 롤업과 비슷한 시간에
  답했습니다(48–50 ms, `uniq` 크기 상태는 49–72 ms). 읽은 바이트는 2.7배였습니다. 10분 롤업은 34–38 ms였습니다.
  원본이 커질 때 이 차이가 어떻게 벌어지는지는 이 실습에서 재지 않았습니다.

### 한계

빌드 하나, 머신 하나, 합성 데이터입니다. 사용자는 50만 명에서 고르게 뽑고 한 페이지에 고정했으므로, 그룹당
고유 수는 페이지 분포를 따르고 실제 워크로드를 따르지 않습니다. 크기는 `OPTIMIZE … FINAL` 뒤의 값이고,
운영 중인 롤업에는 병합되지 않은 부분 상태도 있습니다. 시간은 캐시가 데워진 상태(다섯 번 중 중앙값)이고
다른 컨테이너가 돌고 있었습니다. `uniqCombined(12)` 차이 개수는 실행마다 달라집니다(위 참고).
