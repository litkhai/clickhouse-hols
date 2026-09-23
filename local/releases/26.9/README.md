# ClickHouse 26.9

[English](#english) | [한국어](#한국어)

---

## English

**Released 2026-09-21 · verified here against 26.9.1.1629**

26.9 is the release after an LTS, and it spends that position on cleanup: the
changelog has 17 backward incompatible changes against 27 new features, and
several of the removals are things that had been deprecated for years. The
analyzer can no longer be switched off. CatBoost, `WINDOW VIEW` and WasmEdge
are gone. The default compression codec changed.

This lab takes four of them that you can see working in a single container.

| Lab | Feature | Why it is here |
|-----|---------|----------------|
| [01](01-limit-after-until.sql) | `LIMIT ... AFTER` / `UNTIL` | The first `LIMIT` that cuts on a condition instead of a position. Expresses queries `WHERE` cannot |
| [02](02-keyvaluepairs-index.sql) | `keyValuePairs` text index tokenizer | Indexes a `Map` column directly — the end of promoting hot keys to columns |
| [03](03-zstd-default.sql) | `ZSTD(3)` as the default codec | The change most likely to alter your disk usage without you asking |
| [04](04-create-token.sql) | `CREATE TOKEN`, scoped `GRANTS` | Credentials strictly weaker than the user that issued them |

### Quick start

```bash
./00-setup.sh              # brings up ClickHouse 26.9 via local/oss-mac-setup
./01-limit-after-until.sh
./02-keyvaluepairs-index.sh
./03-zstd-default.sh       # writes and merges ~26M rows, allow a couple of minutes
./04-create-token.sh
```

Each `NN-*.sh` pipes the matching `.sql` into `clickhouse-client`. Read the SQL
— the comments are the lab. `04-create-token.sh` is the exception: it adds
connections of its own, for the reason given in lab 04 below.

---

### 01 · `LIMIT ... AFTER` / `UNTIL`

```sql
SELECT number FROM numbers(10) ORDER BY number LIMIT 3 AFTER number >= 5;  -- 5, 6, 7
SELECT number FROM numbers(10) ORDER BY number LIMIT UNTIL number >= 3;    -- 0, 1, 2
```

Every `LIMIT` ClickHouse had before this counted positions. These four forms
cut the stream at a row that *satisfies a condition*, following the stream
order — so `ORDER BY` is what defines "before" and "after":

| Form | Returns |
|------|---------|
| `LIMIT n AFTER cond` | up to `n` rows starting at the first row where `cond` holds |
| `LIMIT UNTIL cond` | the rows before the first row where `cond` holds |
| `LIMIT AFTER c1 UNTIL c2` | the rows between the two |
| `LIMIT n AFTER cond ALL` | an `n`-row window at **every** matching row, unioned without duplicates |

**The reason to learn them is that `WHERE` cannot say this.** `WHERE` tests
each row on its own, so it keeps the rows that pass *after* the interesting
one too:

```text
rows:  1 ok   2 ok   3 error   4 ok   5 error   6 ok

WHERE lvl != 'error'         → [1, 2, 4, 6]
LIMIT UNTIL lvl = 'error'    → [1, 2]
```

"What happened up to the first error" has no `WHERE` spelling. It used to need
a window function or a self-join to find the boundary row first.

**`ALL` is the log reader's form.** `LIMIT 2 AFTER lvl = 'error' ALL` opens a
window at every error and returns their union — the error and its next line,
for all of them, in one query. Overlapping windows are merged, not repeated:
`LIMIT 3 AFTER number IN (2, 3) ALL` gives `[2,3,4,5]`, not seven rows.

**It stops reading.** This is not a filter applied after the scan. Over
100 million rows with `max_block_size = 1000`, `LIMIT UNTIL number >= 10`
reports `read_rows = 1000` in `system.query_log` — one block.

**Two things to know before you use them:**

- The condition column does not have to be in the `SELECT` list. It is
  evaluated against the stream, not the projection.
- `OFFSET` does not combine with these forms — `LIMIT 3 AFTER cond OFFSET 1`
  is a syntax error. Nest the query and apply a positional `LIMIT` outside it.

And the asymmetry when nothing matches is the right one: `AFTER` has no window
to open, so it returns nothing; `UNTIL` never finds a place to stop, so it
returns everything.

---

### 02 · `keyValuePairs` text index tokenizer

```sql
CREATE TABLE kvp (
    ts    DateTime,
    attrs Map(String, String),
    INDEX idx_attrs attrs TYPE text(tokenizer = keyValuePairs) GRANULARITY 1
) ENGINE = MergeTree ORDER BY ts;
```

Observability schemas put the variable part of a row in a `Map(String,
String)`. Until 26.9 the only ways to make `attrs['service'] = 'checkout'`
fast were to guess the hot keys in advance and promote them to real columns,
or to read the map column on every query. `keyValuePairs` indexes the map
itself: each entry becomes one token of key and value joined together.

**What it buys.** Two million rows, `tenant` clustered 100k rows to a value:

| | `read_rows` | `read_bytes` | `query_duration_ms` |
|---|---:|---:|---:|
| with the index | 2 | 32 B | 4 |
| without | 2,000,000 | 10.49 MiB | 13 |

The indexed `count()` never opens the map column at all — the plan node is
`ReadFromTextIndexCount`, not `ReadFromMergeTree`. A text index knows how many
rows carry a token, so a count is answered out of the index. For a query that
needs an actual column it goes back to being a skip index: `13/245` granules
survive, with a `PREWHERE` to recheck them.

**The limitation to plan around.** The token is the key and the value
concatenated with a separator — `EXPLAIN indexes = 1` shows
`tokens: ["tenantt7\f"]`. Only whole-value equality can be looked up. Four
reasonable-looking predicates compile fine and scan every granule:

| Predicate | Index |
|-----------|-------|
| `attrs['k'] = 'v'` | ✅ |
| `attrs['k'] = 'v' AND attrs['j'] = 'w'` | ✅ mode `All`, both tokens |
| `attrs['k'] = 'v' OR attrs['k'] = 'w'` | ✅ mode `Any` |
| `attrs['k'] IN ('v', 'w')` | ❌ full scan |
| `attrs['k'] LIKE 'v%'` | ❌ no partial-value token exists |
| `mapContains(attrs, 'k')` | ❌ a key with no value is not a token |
| `attrs['k'] != 'v'` | ❌ absence of a token proves nothing |

**`IN` is the trap.** It means the same thing to a reader as the `OR` above it
and prunes nothing, so a fast query gets slow the day somebody tidies it into
an `IN` list. That is worth a comment in the schema.

There is also no way past the `map['key'] = 'value'` form — `hasToken(attrs,
…)` rejects a `Map` argument outright. The equality is the whole interface.

This is the third release running to extend text indexes: 26.8 added the
`japanese`, `chinese` and `icu` tokenizers, and 26.9 also gives
`splitByRegexp` an `extract` argument, so `tokens(s, 'splitByRegexp',
'[a-z]=([0-9]+)', 1)` returns the capture groups rather than the separators.

---

### 03 · `ZSTD(3)` as the default codec

26.9 changes what ClickHouse compresses with when you do not say. It is listed
under backward incompatible changes even though nothing breaks — every
compressed frame is self-describing, so old data keeps reading.

Three separate things changed, and conflating them is how people end up
surprised:

| What | New default |
|------|-------------|
| Client/server, server/server, HTTP `compress=1` | `ZSTD(3)` uniformly |
| `MergeTree` column data | **size-aware** — `LZ4` below 100 MB, `ZSTD(3)` at or above |
| `StripeLog`, `Set`/`Join` engine files, `checksums.txt` | `ZSTD(3)` uniformly |

**The size rule has a consequence that is easy to read past.** It is judged by
"the part size known at write time (the size of the source parts for a merge or
a mutation)" — and a plain `INSERT` does not know how big its part will be. So
freshly inserted data is `LZ4` *whatever its size*. `ZSTD(3)` arrives later,
when merges have accumulated enough of it. Measured on the same table:

```text
                 compressed    ratio
before merge      111.70 MiB    7.69     two 6.5M-row inserts
after merge        21.53 MiB   39.88     merged, source parts ~112 MB
```

No rows were removed and nothing in the table definition changed. A 6.5M-row
insert on its own stays at ~8x; only the merge crosses the threshold.

The operational reading: on a new cluster your newest data is `LZ4` and your
settled data is `ZSTD(3)`, and disk usage keeps falling behind you as merges
catch up. Capacity planning off a day-one measurement will overshoot.

**Rolling it back is not one switch.** `compatibility = '26.8'` does restore
`LZ4` for `network_compression_method` — the lab prints `ZSTD`, `LZ4`, `LZ4`
for 26.9, 26.8 and 25.1. It does **not** restore the `MergeTree` column
default; a merge run under `compatibility = '26.8'` still comes out at 39.88x.
For column data the levers are `CODEC(LZ4)` on the column or table, or the
server-level `<compression>` default.

**Two things that are not part of this change**, worth knowing before you go
hunting a regression: `marks_compression_codec` and
`primary_key_compression_codec` have defaulted to `ZSTD(3)` for several
releases already.

`system.parts.default_compression_codec` reports the table's declared default,
not what the size rule chose — it says `LZ4` even for a table whose every
column carries an explicit `CODEC(ZSTD(3))`. Measure the ratio instead.

---

### 04 · `CREATE TOKEN` and scoped `GRANTS`

```sql
CREATE TOKEN VALID FOR INTERVAL 30 DAY GRANTS (SELECT ON demo.events);
```

An authentication method can now carry its own grant list. A session that logs
in with that method gets the **intersection** of the user's privileges and the
listed ones, so one user can hand out credentials strictly weaker than itself
without a second user, a second role, or a proxy in front.

`CREATE TOKEN` is the self-service form — it generates the secret, attaches it
to the current user, and returns it with its deadline:

```text
token:       WzZjScwypyT3AiodtEFOyI1YslQFSrEm
valid_until: 2026-10-23 11:01:32
```

`ALTER USER u ADD IDENTIFIED WITH … VALID UNTIL … GRANTS (…)` is the
administrator's form, doing the same to somebody else with a secret you pick.

**Two things stop `CREATE TOKEN` working, and both look like bugs the first
time:**

- The user must live in a writable access storage. The `default` user of the
  official Docker image is defined in `users.xml`, which is read-only:
  `Code: 495. Cannot update user 'default' in users_xml because this storage
  is readonly.` SQL-defined users are fine. This is why lab 04's `.sql` uses
  the `ALTER USER` form and the runner does the `CREATE TOKEN` half.
- A token is an *additional* authentication method, and `no_password` cannot
  co-exist with any other: `Code: 36`. The user needs a real credential first.

Also, the privilege needs the `ON *.*` form — `GRANT CREATE TOKEN TO app` is a
syntax error, `GRANT CREATE TOKEN ON *.* TO app` is not.

**What the scope actually does**, with `app` granted `SELECT ON demo.*` and a
token scoped to `SELECT ON demo.events`:

| | `demo.events` | `demo.secrets` |
|---|---|---|
| full password | 2 rows | 1 row |
| scoped token | 2 rows | `Code: 497 … ACCESS_DENIED` |

**The obvious escalation is closed.** A session authenticated with a scoped
method cannot mint another token: *"the current session is authenticated with
a method which limits the access rights with the GRANTS clause, and such
sessions cannot add authentication methods to an existing user."*

**Operational notes, all demonstrated in the lab:**

- Expiry is checked at login, not at issue. `VALID UNTIL '2020-01-01'` is
  accepted without complaint and then refuses every login with
  `AUTHENTICATION_FAILED`. A deploy script that computes the deadline in the
  wrong timezone gets no error where you would want one.
- The default TTL without a `VALID` clause is `create_token_default_ttl_seconds`
  — 1800, thirty minutes. Short on purpose.
- There is no `DROP TOKEN`. `ALTER USER u IDENTIFIED WITH …` (without `ADD`)
  replaces the whole method list, which revokes every token at once. Revoking
  one and keeping the rest means re-issuing the rest, so plan one token per
  consumer.
- `SHOW CREATE USER` is the only place the scope is visible. `system.users`
  shows nothing but a list of identical `sha256_password` entries.

---

### Also in 26.9, not covered by these labs

The changelog runs to 17 backward incompatible changes, 27 new features, 28
experimental features and 135 performance improvements. In rough order of how
likely they are to affect you:

**Removals and breaking changes**

| | |
|---|---|
| **The analyzer can no longer be disabled** | `enable_analyzer = 0` is rejected outright (`Code: 452`), and `compatibility` no longer reverts it. Default since 24.3; to compare against the old analysis you now need a pre-26.9 binary |
| **CatBoost removed** | `catboostEvaluate`, `system.models`, `SYSTEM RELOAD MODEL(S)`. Revoke `SYSTEM RELOAD MODEL` from every user, role, `users.xml` and access backup **before** upgrading — an access entity carrying the removed privilege cannot be parsed, and a replica will silently drop it |
| **`WINDOW VIEW` removed** | With `WATCH` and `windowID`. Non-functional since 24.12 and never supported by the analyzer. A server that finds a window view in its metadata **fails to start** — drop them first. `tumble`/`hop` and friends stay |
| **`Nullable(Tuple(...))` is GA** | Schema inference in Parquet/Arrow/ORC/Avro/JSON now returns it, and tuple subcolumns of `Variant`/`Dynamic`/`JSON` are `NULL` where missing instead of a tuple of defaults. If a partition key, sorting key, TTL or skip index depends on such a subcolumn, set `allow_nullable_tuple_in_extracted_subcolumns = 0` in the default profile **before** the first restart or parts may detach |
| `interface` / `http_method` become `Enum8` | In `query_log`, `query_thread_log` and `processes`. `WHERE interface = 1` still works, `WHERE interface = 'TCP'` now works too, `interface + 0` does not. Existing log tables are renamed to `query_log_0` and so on at upgrade |
| WasmEdge engine removed | `wasmtime` is the only `webassembly_udf_engine`. A server configured for `wasmedge` will not start |
| Sharded `GROUP BY` removed | `enable_sharding_aggregator` is an accepted no-op; `enable_adaptive_aggregator` covers the same workloads |
| `s3_disable_checksum` removed | The checksum is computed during the single read, so there is nothing to disable |
| `read_resource` / `write_resource` disk options removed | Use `CREATE RESOURCE name (READ DISK d, WRITE DISK d)` |
| `runningConcurrency` is now non-deterministic | Fixes wrong results under `LEFT`/`ANY JOIN` and lazy `if`/`multiIf`. A table with it in a sorting or partition key **will not load** after the upgrade |
| Codecs gated per codec | `allow_experimental_codecs` is obsolete; use `enable_<codec>_codec`. `ALP` is promoted to beta via `enable_alp_codec` |
| `BACKUP`/`RESTORE ... Disk(...)` need `SOURCES` grants | `WRITE ON DISK` to write, `READ ON DISK` to read, on top of `BACKUP` |
| `File` + `rename_files_after_processing` needs `WRITE ON FILE` | The setting renames what a `SELECT` read, which is a write |
| `CREATE TABLE ... AS mergeTreeIndex(...)` rejected | Also `mergeTreeProjection`, `mergeTreeTextIndex`, `timeSeriesSamples`, `timeSeriesData` and siblings. Such a table made `DROP TABLE <source> SYNC` hang forever. Find them with `SELECT database, name FROM system.tables WHERE engine = 'Proxy'`. Reading the functions directly is unaffected |
| `validate_group_by_all_key_types` | New setting, default on, gating the `GROUP BY ALL` key-type check that has rejected `Variant`/`Dynamic` keys since 26.7 |

**New features**

| | |
|---|---|
| `DISTINCT` spills to disk | `max_bytes_before_external_distinct`, `max_bytes_ratio_before_external_distinct` (0.5). Like external aggregation and sort, on by ratio |
| `REFRESH ... APPEND INCREMENTAL` | Refreshable materialized views append only rows committed since the last refresh. Into an `Iceberg` target it is exactly-once — the cursor commits inside the snapshot summary |
| `max_table_size_rows` / `_bytes_compressed` / `_bytes_uncompressed` | `MergeTree` settings capping total table size, checked on `INSERT` and on part commit including merges, but not on replicated fetches |
| `max_tables` database setting | `CREATE DATABASE d SETTINGS max_tables = 2` → `Code: 724. Too many tables`. Counts views and dictionaries too |
| `regr_slope`, `regr_intercept`, `regr_r2`, `regr_count`, `regr_avgx`, `regr_avgy`, `regr_sxx`, `regr_syy`, `regr_sxy` | The SQL-standard linear regression aggregates |
| Bracket syntax for `JSON` subcolumns | `json['a']['b']`, translated to nested `arrayElement` |
| `system.statements` | 101 rows of SQL statement documentation — name, syntax, description, examples. Lab 04 reads `CREATE TOKEN` out of it |
| `system.session_query_ids` | The query ids of this session in execution order, so "the queries I just ran" needs no client-side `query_id` or `log_comment`. Bounded by `session_query_ids_history_size` (1000) |
| `arrayFlattenedLength` | Counts elements at every nesting level — `[[1,2],[3],[4,5,6]]` is 6, where `length` is 3. Matches PostgreSQL's `cardinality` |
| `parseISO8601Duration` | `'PT1H30M'` → 5400 |
| `DateTime` + `Time` arithmetic | `toDateTime('2026-09-23 00:00:00') + toTime('01:30:00')` |
| `splitByRegexp` `extract` argument | `tokens(s, 'splitByRegexp', re, 1)` returns each match's first capture group instead of splitting on it |
| `skip_empty_columns_on_insert` | Opt-in `MergeTree` setting that omits columns holding only type defaults. Needs `serialization_info_version = 'with_missing_columns'` — keep the old version during a rolling upgrade |
| `type_json_skip_null_typed_paths` | Treats `NULL` typed paths in `JSON` as absent, matching dynamic paths |
| jemalloc fragmentation profiler | `system.jemalloc_sampled_allocations` with backtrace, age and size class, plus a Fragmentation tab in the server web UI |
| `BACKUP`/`RESTORE` for `WORKLOAD` and `RESOURCE` | SQL-defined definitions are included and recreated, `ON CLUSTER` too |
| `workload_admission_timeout_ms` | Bounds the wait for a workload query slot; `0` keeps the old unbounded wait |
| `S3Queue` `mode = 'exclusive'` | Processing tracked in server memory with no Keeper coordination, for single-server high-throughput ingest |
| `nats_ca_file` / `nats_client_cert_file` / `nats_client_key_file` | Private-CA verification and client-certificate auth for the `NATS` engine |
| `clickhouse-client --ssh-key-file` with no value | Resolves the key the way `ssh` does, including from `ssh-agent` |
| Iceberg v3 `first_row_id` / `last_seq_num` | Exposed as virtual columns and written on insert |
| `keeper` four-letter-word for leader backpressure | Against slow Raft members |

> The changelog also lists a zero-argument `year()` returning the current year.
> It is **not** in 26.9.1.1629 — `SELECT year()` still resolves to `toYear` and
> fails with `NUMBER_OF_ARGUMENTS_DOESNT_MATCH`. Expect it in a later build.

**Experimental**

| | |
|---|---|
| Embedded SQL Console at `/ui` | The ClickHouse Cloud console, served by the HTTP server. Returns 200 in the lab container; not the same thing as `/play` |
| `TimeSeries` and PromQL | `SELECT` support for `TimeSeries` tables; the outer samples column renamed `samples`; `METRICS` renamed `METRIC FAMILIES` (old name still an alias); `LowCardinality` series ids by default, quoted at 1.16x geomean PromQL speedup. PromQL gains `absent`, `count_values`, `sum_over_time`, `avg_over_time`, `count_over_time`, `present_over_time`, `absent_over_time`, `quantile_over_time`, `predict_linear`, `max_over_time`, `min_over_time`. See the [TimeSeries + PromQL lab](../../../usecase/timeseries-promql-oss/) for the engine itself |
| Prometheus HTTP API | `/api/v1/metadata`, `/api/v1/labels`, `/api/v1/label/<name>/values` and `/api/v1/format_query` |
| `trino` dialect | `enable_trino_dialect` translates Trino SQL — `ARRAY[...]`, `TRY_CAST`, `UNNEST`, `ROW`, `FETCH`, `OFFSET` before `LIMIT`, and several hundred function mappings |
| `KQL` reimplemented | A real lexer and parser instead of translating to SQL text and reparsing. Fixes expression injection in `contains`/`has` and several results that disagreed with Kusto. Unsupported syntax is now rejected rather than mistranslated |
| `DeltaLake` `CREATE TABLE` | Writes the initial commit through `delta-kernel-rs`, attaches to an existing `_delta_log`, or registers into Unity. Behind `allow_delta_lake_create_table`; no `PARTITION BY` yet. Writes now cast accurately and throw on overflow (`delta_lake_accurate_write_cast`) |
| `hierarchicalKMeans`, `assignCentroid` | Building blocks for IVF-style vector search |
| Parallel replicas | `parallel_replicas_plan_based` can now enable itself from runtime statistics, supports `RIGHT JOIN` and `ORDER BY ... WITH FILL`, and reads `Merge` tables with `parallel_replicas_allow_merge_tables` |
| Distributed plans | `make_distributed_plan` stops idle upstream stages after a satisfied `LIMIT`, honours `max_threads` in worker fragments, drops up to 100 ms of idle wait per finished stage, and supports `INTERSECT`/`EXCEPT` |
| Adaptive codec selection | `enable_adaptive_codec_selection` now covers columns with no specialized candidate (picking the smaller of the default and `NONE`, so incompressible data is never stored larger than raw), every substream including `Array`/`String` sizes and null maps, and `ALP` for floats |
| `silk` fiber runtime | `enable_silk_runtime`; subsystems that support it run jobs on fibers instead of blocking an OS thread on I/O |
| Cascades eager aggregation | `cascades_aggregation_pushdown` pushes a partial aggregation below a `JOIN` as a cost-based choice |

### Verified

Every query in the four `.sql` files was run against **26.9.1.1629** in the
container this lab sets up, and every number, plan fragment and error code
quoted above is from those runs. `04-create-token.sh` was run end to end too.

Two things were worked around while writing, both noted in the SQL:

- `UNION ALL` does not expose its column aliases to a trailing `ORDER BY`, so
  the comparison tables in labs 01, 03 and 04 wrap the union before sorting.
  This is the same trap the 26.8 lab hit.
- A refused login raises an exception, which would stop a `.sql` file at that
  line. Lab 04 therefore keeps its `.sql` exception-free and puts the
  `ACCESS_DENIED` and `AUTHENTICATION_FAILED` demonstrations in the `.sh`
  runner, one connection each.

One changelog claim did not hold on this build and is flagged above: the
zero-argument `year()`.

---

## 한국어

**2026-09-21 릴리스 · 여기서는 26.9.1.1629로 검증**

26.9는 LTS 다음 릴리스이고, 그 자리를 정리에 씁니다 — changelog에 하위 호환성
변경 17개에 신기능 27개입니다. 제거된 것 중 상당수는 수년간 deprecated 상태였던
것들입니다. 애널라이저를 더 이상 끌 수 없고, CatBoost·`WINDOW VIEW`·WasmEdge가
사라졌으며, 기본 압축 코덱이 바뀌었습니다.

이 랩은 그중 **컨테이너 하나에서 눈으로 확인할 수 있는** 네 가지를 다룹니다.

| 랩 | 기능 | 선정 이유 |
|----|------|-----------|
| [01](01-limit-after-until.sql) | `LIMIT ... AFTER` / `UNTIL` | 위치가 아니라 조건으로 자르는 첫 `LIMIT`. `WHERE`로는 쓸 수 없는 쿼리를 표현 |
| [02](02-keyvaluepairs-index.sql) | `keyValuePairs` 텍스트 인덱스 토크나이저 | `Map` 컬럼을 직접 색인 — 자주 쓰는 키를 컬럼으로 승격하던 관행의 끝 |
| [03](03-zstd-default.sql) | 기본 코덱 `ZSTD(3)` | 요청하지 않아도 디스크 사용량을 바꿀 가능성이 가장 큰 변화 |
| [04](04-create-token.sql) | `CREATE TOKEN`, 범위 제한 `GRANTS` | 발급한 사용자보다 반드시 약한 자격 증명 |

### 빠른 시작

```bash
./00-setup.sh              # local/oss-mac-setup으로 26.9 기동
./01-limit-after-until.sh
./02-keyvaluepairs-index.sh
./03-zstd-default.sh       # 약 2,600만 행을 쓰고 병합하므로 몇 분 걸립니다
./04-create-token.sh
```

각 `NN-*.sh`는 같은 이름의 `.sql`을 `clickhouse-client`에 넘깁니다. SQL을
읽으세요 — 주석이 곧 랩입니다. `04-create-token.sh`만 예외로 자체 연결을
추가하는데, 이유는 아래 랩 04에 있습니다.

---

### 01 · `LIMIT ... AFTER` / `UNTIL`

```sql
SELECT number FROM numbers(10) ORDER BY number LIMIT 3 AFTER number >= 5;  -- 5, 6, 7
SELECT number FROM numbers(10) ORDER BY number LIMIT UNTIL number >= 3;    -- 0, 1, 2
```

이전까지 ClickHouse의 `LIMIT`은 모두 **위치**를 셌습니다. 새 네 가지 형태는
**조건을 만족하는 행**에서 스트림을 자르며, 스트림 순서를 따릅니다 — 즉
"앞"과 "뒤"를 정의하는 것은 `ORDER BY`입니다.

| 형태 | 반환 |
|------|------|
| `LIMIT n AFTER cond` | `cond`가 처음 참이 되는 행부터 최대 `n`행 |
| `LIMIT UNTIL cond` | `cond`가 처음 참이 되는 행 **직전까지** |
| `LIMIT AFTER c1 UNTIL c2` | 두 지점 사이 |
| `LIMIT n AFTER cond ALL` | **매칭되는 모든 행**마다 `n`행 창을 열고 중복 없이 합집합 |

**배워야 하는 이유는 `WHERE`로 이 말을 할 수 없기 때문입니다.** `WHERE`는 각
행을 개별로 판정하므로, 문제의 행 **이후**에 나오는 통과 행들도 함께
남깁니다.

```text
행:  1 ok   2 ok   3 error   4 ok   5 error   6 ok

WHERE lvl != 'error'         → [1, 2, 4, 6]
LIMIT UNTIL lvl = 'error'    → [1, 2]
```

"첫 에러 직전까지 무슨 일이 있었나"는 `WHERE`로 쓸 방법이 없습니다. 예전에는
경계 행을 먼저 찾기 위해 윈도우 함수나 셀프 조인이 필요했습니다.

**`ALL`은 로그를 읽는 사람의 형태입니다.** `LIMIT 2 AFTER lvl = 'error' ALL`은
모든 에러마다 창을 열고 합집합을 반환합니다 — 에러와 그 다음 줄을, 전부, 쿼리
하나로. 겹치는 창은 반복되지 않고 병합됩니다:
`LIMIT 3 AFTER number IN (2, 3) ALL`은 7행이 아니라 `[2,3,4,5]`입니다.

**읽기를 멈춥니다.** 스캔 후에 거는 필터가 아닙니다. 1억 행에
`max_block_size = 1000`으로 `LIMIT UNTIL number >= 10`을 걸면
`system.query_log`의 `read_rows`가 **1000** — 블록 하나입니다.

**쓰기 전에 알아야 할 두 가지:**

- 조건 컬럼이 `SELECT` 목록에 있을 필요는 없습니다. 조건은 프로젝션이 아니라
  스트림에 대해 평가됩니다.
- `OFFSET`은 이 형태들과 결합되지 않습니다 — `LIMIT 3 AFTER cond OFFSET 1`은
  문법 오류입니다. 쿼리를 감싸고 바깥에서 위치 기반 `LIMIT`을 거세요.

아무것도 매칭되지 않을 때의 비대칭은 올바른 방향입니다. `AFTER`는 열 창이
없으므로 아무것도 반환하지 않고, `UNTIL`은 멈출 지점을 못 찾으므로 전부
반환합니다.

---

### 02 · `keyValuePairs` 텍스트 인덱스 토크나이저

```sql
CREATE TABLE kvp (
    ts    DateTime,
    attrs Map(String, String),
    INDEX idx_attrs attrs TYPE text(tokenizer = keyValuePairs) GRANULARITY 1
) ENGINE = MergeTree ORDER BY ts;
```

관측성 스키마는 행의 가변 부분을 `Map(String, String)`에 담습니다. 26.9
이전에는 `attrs['service'] = 'checkout'`를 빠르게 만들려면 자주 쓰는 키를 미리
짐작해 실제 컬럼으로 승격하거나, 매 쿼리마다 맵 컬럼을 읽는 수밖에
없었습니다. `keyValuePairs`는 맵 자체를 색인합니다 — 각 엔트리가 키와 값을
이어붙인 토큰 하나가 됩니다.

**얻는 것.** 200만 행, `tenant`는 10만 행마다 한 값으로 뭉쳐 있습니다.

| | `read_rows` | `read_bytes` | `query_duration_ms` |
|---|---:|---:|---:|
| 인덱스 있음 | 2 | 32 B | 4 |
| 없음 | 2,000,000 | 10.49 MiB | 13 |

인덱스가 있는 `count()`는 맵 컬럼을 아예 열지 않습니다 — 플랜 노드가
`ReadFromMergeTree`가 아니라 `ReadFromTextIndexCount`입니다. 텍스트 인덱스는
토큰을 가진 행 수를 알고 있으므로 카운트를 인덱스에서 바로 답합니다. 실제
컬럼이 필요한 쿼리에서는 다시 스킵 인덱스로 동작해 `13/245` 그래뉼만 남기고
`PREWHERE`로 재확인합니다.

**반드시 감안해야 할 한계.** 토큰은 키와 값을 구분자로 이어붙인 것입니다 —
`EXPLAIN indexes = 1`에 `tokens: ["tenantt7\f"]`로 보입니다. 즉 **값 전체
동등 비교만** 조회할 수 있습니다. 그럴듯해 보이는 술어 넷은 문제없이
컴파일되고 모든 그래뉼을 스캔합니다.

| 술어 | 인덱스 |
|------|--------|
| `attrs['k'] = 'v'` | ✅ |
| `attrs['k'] = 'v' AND attrs['j'] = 'w'` | ✅ mode `All`, 토큰 둘 다 |
| `attrs['k'] = 'v' OR attrs['k'] = 'w'` | ✅ mode `Any` |
| `attrs['k'] IN ('v', 'w')` | ❌ 전체 스캔 |
| `attrs['k'] LIKE 'v%'` | ❌ 부분 값 토큰이 존재하지 않음 |
| `mapContains(attrs, 'k')` | ❌ 값 없는 키는 토큰이 아님 |
| `attrs['k'] != 'v'` | ❌ 토큰의 부재는 아무것도 증명하지 못함 |

**함정은 `IN`입니다.** 읽는 사람에게는 바로 위의 `OR`와 같은 뜻인데 아무것도
가지치기하지 않습니다. 누군가 `IN` 목록으로 "정리"하는 날 빠르던 쿼리가
느려집니다. 스키마에 주석을 남겨 둘 만합니다.

`map['key'] = 'value'` 형태를 우회할 방법도 없습니다 — `hasToken(attrs, …)`은
`Map` 인자를 아예 거부합니다. 이 동등 비교가 인터페이스의 전부입니다.

텍스트 인덱스 확장은 이번이 세 번째 릴리스 연속입니다. 26.8이
`japanese`·`chinese`·`icu` 토크나이저를 추가했고, 26.9는 `splitByRegexp`에
`extract` 인자도 줍니다 — `tokens(s, 'splitByRegexp', '[a-z]=([0-9]+)', 1)`은
구분자가 아니라 캡처 그룹을 반환합니다.

---

### 03 · 기본 코덱이 된 `ZSTD(3)`

26.9는 코덱을 지정하지 않았을 때 ClickHouse가 무엇으로 압축하는지를 바꿉니다.
깨지는 것은 없지만 하위 호환성 변경으로 분류돼 있습니다 — 압축 프레임은 모두
자기 기술적이라 기존 데이터는 그대로 읽힙니다.

바뀐 것은 세 가지이고, 이걸 뭉뚱그리는 데서 오해가 생깁니다.

| 대상 | 새 기본값 |
|------|-----------|
| 클라이언트/서버, 서버/서버, HTTP `compress=1` | 일괄 `ZSTD(3)` |
| `MergeTree` 컬럼 데이터 | **크기 기준** — 100 MB 미만 `LZ4`, 이상 `ZSTD(3)` |
| `StripeLog`, `Set`/`Join` 엔진 파일, `checksums.txt` | 일괄 `ZSTD(3)` |

**크기 규칙에는 그냥 지나치기 쉬운 결과가 하나 있습니다.** 판정 기준은
"쓰기 시점에 알 수 있는 파트 크기(병합·뮤테이션의 경우 소스 파트 크기)"인데,
일반 `INSERT`는 자기 파트가 얼마나 커질지 모릅니다. 그래서 **방금 삽입된
데이터는 크기와 무관하게 `LZ4`**입니다. `ZSTD(3)`은 나중에, 병합이 충분히
쌓은 뒤에 도착합니다. 같은 테이블에서 측정한 결과입니다.

```text
              압축 후      비율
병합 전     111.70 MiB    7.69     650만 행 INSERT 두 번
병합 후      21.53 MiB   39.88     병합, 소스 파트 약 112 MB
```

행이 삭제된 것도 아니고 테이블 정의가 바뀐 것도 아닙니다. 650만 행 INSERT
하나만으로는 약 8배에 머무르고, 병합만이 임계값을 넘습니다.

운영 관점의 해석: 새 클러스터에서 **최신 데이터는 `LZ4`, 안정된 데이터는
`ZSTD(3)`**이고, 병합이 따라오면서 디스크 사용량이 계속 줄어듭니다. 첫날
측정값으로 용량을 산정하면 과대 추정하게 됩니다.

**되돌리는 방법은 스위치 하나가 아닙니다.** `compatibility = '26.8'`은
`network_compression_method`를 `LZ4`로 되돌립니다 — 랩은 26.9·26.8·25.1에
대해 `ZSTD`, `LZ4`, `LZ4`를 출력합니다. 하지만 `MergeTree` 컬럼 기본값은
되돌리지 **않습니다**. `compatibility = '26.8'`로 실행한 병합도 39.88배로
나옵니다. 컬럼 데이터의 레버는 컬럼·테이블의 `CODEC(LZ4)`, 또는 서버 수준
`<compression>` 기본값입니다.

**이 변화에 포함되지 않는 두 가지**도 알아 두세요. 회귀를 찾아 헤매기 전에:
`marks_compression_codec`과 `primary_key_compression_codec`은 이미 여러
릴리스 전부터 `ZSTD(3)`이 기본이었습니다.

`system.parts.default_compression_codec`은 크기 규칙이 고른 값이 아니라
테이블에 선언된 기본값을 보고합니다 — 모든 컬럼에 `CODEC(ZSTD(3))`을 명시한
테이블에서도 `LZ4`라고 나옵니다. 비율을 측정하세요.

---

### 04 · `CREATE TOKEN`과 범위 제한 `GRANTS`

```sql
CREATE TOKEN VALID FOR INTERVAL 30 DAY GRANTS (SELECT ON demo.events);
```

이제 인증 수단이 자기 권한 목록을 가질 수 있습니다. 해당 수단으로 로그인한
세션은 사용자 권한과 명시된 권한의 **교집합**을 갖습니다. 즉 사용자 하나가
자기보다 반드시 약한 자격 증명을 발급할 수 있습니다 — 두 번째 사용자도, 두
번째 역할도, 앞단 프록시도 없이.

`CREATE TOKEN`은 셀프서비스 형태입니다. 시크릿을 생성해 현재 사용자에 붙이고
만료 시각과 함께 돌려줍니다.

```text
token:       WzZjScwypyT3AiodtEFOyI1YslQFSrEm
valid_until: 2026-10-23 11:01:32
```

`ALTER USER u ADD IDENTIFIED WITH … VALID UNTIL … GRANTS (…)`는 관리자
형태로, 직접 고른 시크릿으로 다른 사용자에게 같은 일을 합니다.

**`CREATE TOKEN`이 동작하지 않게 만드는 두 가지가 있고, 둘 다 처음에는 버그처럼
보입니다.**

- 사용자가 **쓰기 가능한 access storage**에 있어야 합니다. 공식 Docker
  이미지의 `default` 사용자는 읽기 전용인 `users.xml`에 정의돼 있습니다:
  `Code: 495. Cannot update user 'default' in users_xml because this storage
  is readonly.` SQL로 만든 사용자는 괜찮습니다. 랩 04의 `.sql`이 `ALTER USER`
  형태를 쓰고 `CREATE TOKEN` 쪽은 러너가 담당하는 이유입니다.
- 토큰은 **추가** 인증 수단이고, `no_password`는 다른 수단과 공존할 수
  없습니다 (`Code: 36`). 사용자에게 먼저 실제 자격 증명이 있어야 합니다.

권한도 `ON *.*` 형태가 필요합니다 — `GRANT CREATE TOKEN TO app`은 문법
오류이고, `GRANT CREATE TOKEN ON *.* TO app`은 아닙니다.

**범위가 실제로 하는 일.** `app`에 `SELECT ON demo.*`를 주고, 토큰은
`SELECT ON demo.events`로 제한했을 때:

| | `demo.events` | `demo.secrets` |
|---|---|---|
| 전체 비밀번호 | 2행 | 1행 |
| 범위 제한 토큰 | 2행 | `Code: 497 … ACCESS_DENIED` |

**뻔한 권한 상승 경로는 막혀 있습니다.** 범위 제한 수단으로 인증된 세션은 또
다른 토큰을 발급할 수 없습니다 — *"현재 세션은 GRANTS 절로 접근 권한을
제한하는 수단으로 인증되었으며, 그런 세션은 기존 사용자에게 인증 수단을 추가할
수 없습니다."*

**운영상 유의점, 모두 랩에서 실증합니다:**

- 만료는 **발급 시점이 아니라 로그인 시점에** 검사합니다. `VALID UNTIL
  '2020-01-01'`은 아무 불평 없이 수락되고, 이후 모든 로그인을
  `AUTHENTICATION_FAILED`로 거부합니다. 배포 스크립트가 만료 시각을 잘못된
  타임존으로 계산해도 정작 필요한 지점에서는 오류가 나지 않습니다.
- `VALID` 절이 없을 때의 기본 TTL은 `create_token_default_ttl_seconds` —
  1800, 30분입니다. 의도적으로 짧습니다.
- `DROP TOKEN`은 없습니다. `ALTER USER u IDENTIFIED WITH …` (`ADD` 없이)가
  수단 목록 전체를 교체하므로 모든 토큰이 한 번에 폐기됩니다. 하나만 폐기하고
  나머지를 유지하려면 나머지를 재발급해야 하므로, **소비자당 토큰 하나**로
  설계하세요.
- 범위가 보이는 곳은 `SHOW CREATE USER`뿐입니다. `system.users`에는 똑같은
  `sha256_password` 항목들만 나열됩니다.

---

### 26.9의 다른 변화 (이 랩에서 다루지 않음)

changelog에는 하위 호환성 변경 17개, 신기능 27개, 실험 기능 28개, 성능 개선
135개가 있습니다. 영향을 받을 가능성이 큰 순서로 정리했습니다.

**제거 및 파괴적 변경**

| | |
|---|---|
| **애널라이저를 더 이상 끌 수 없음** | `enable_analyzer = 0`은 즉시 거부되고 (`Code: 452`), `compatibility`로도 되돌아가지 않습니다. 24.3부터 기본값이었고, 구 분석과 비교하려면 26.9 이전 바이너리가 필요합니다 |
| **CatBoost 제거** | `catboostEvaluate`, `system.models`, `SYSTEM RELOAD MODEL(S)`. 업그레이드 **전에** 모든 사용자·역할·`users.xml`·access 백업에서 `SYSTEM RELOAD MODEL`을 회수하세요 — 제거된 권한을 가진 access 엔티티는 파싱되지 않고, 레플리카는 이를 조용히 누락시킵니다 |
| **`WINDOW VIEW` 제거** | `WATCH`, `windowID`와 함께. 24.12부터 동작하지 않았고 애널라이저를 지원한 적이 없습니다. 메타데이터에 window view가 있으면 서버가 **기동에 실패**하므로 먼저 드롭하세요. `tumble`·`hop` 계열은 유지 |
| **`Nullable(Tuple(...))` 정식 지원** | Parquet/Arrow/ORC/Avro/JSON 스키마 추론이 이를 반환하고, `Variant`/`Dynamic`/`JSON`의 튜플 서브컬럼은 값이 없을 때 기본값 튜플이 아니라 `NULL`이 됩니다. 파티션 키·정렬 키·TTL·스킵 인덱스가 그런 서브컬럼에 의존한다면 업그레이드 후 **첫 재시작 전에** 기본 프로필에 `allow_nullable_tuple_in_extracted_subcolumns = 0`을 설정하세요. 아니면 파트가 detach될 수 있습니다 |
| `interface` / `http_method`가 `Enum8`으로 | `query_log`·`query_thread_log`·`processes`에서. `WHERE interface = 1`도 되고 `WHERE interface = 'TCP'`도 이제 됩니다. `interface + 0`은 안 됩니다. 기존 로그 테이블은 업그레이드 시 `query_log_0` 식으로 이름이 바뀝니다 |
| WasmEdge 엔진 제거 | `webassembly_udf_engine`은 `wasmtime`만 남습니다. `wasmedge`로 설정된 서버는 기동하지 않습니다 |
| 샤딩 `GROUP BY` 제거 | `enable_sharding_aggregator`는 수락되지만 무동작. `enable_adaptive_aggregator`가 같은 워크로드를 담당합니다 |
| `s3_disable_checksum` 제거 | 체크섬을 단일 읽기 중에 계산하므로 끌 대상이 없습니다 |
| `read_resource` / `write_resource` 디스크 옵션 제거 | `CREATE RESOURCE name (READ DISK d, WRITE DISK d)`를 쓰세요 |
| `runningConcurrency`가 비결정적으로 분류 | `LEFT`/`ANY JOIN`과 지연 평가 `if`/`multiIf`에서의 오답을 고칩니다. 정렬 키·파티션 키에 이 함수를 쓴 테이블은 업그레이드 후 **로드되지 않습니다** |
| 코덱별 게이팅 | `allow_experimental_codecs`는 폐기. `enable_<codec>_codec`을 쓰세요. `ALP`는 `enable_alp_codec`으로 베타 승격 |
| `BACKUP`/`RESTORE ... Disk(...)`에 `SOURCES` 권한 필요 | `BACKUP` 위에 쓰기는 `WRITE ON DISK`, 읽기는 `READ ON DISK` |
| `File` + `rename_files_after_processing`에 `WRITE ON FILE` 필요 | `SELECT`가 읽은 파일의 이름을 바꾸는 것은 쓰기입니다 |
| `CREATE TABLE ... AS mergeTreeIndex(...)` 거부 | `mergeTreeProjection`·`mergeTreeTextIndex`·`timeSeriesSamples`·`timeSeriesData` 등도 동일. 이런 테이블은 `DROP TABLE <source> SYNC`를 영영 반환하지 않게 만들었습니다. `SELECT database, name FROM system.tables WHERE engine = 'Proxy'`로 찾으세요. 함수를 직접 읽는 것은 영향 없음 |
| `validate_group_by_all_key_types` | 신규 설정, 기본 활성. 26.7부터 `Variant`/`Dynamic` 키를 거부해 온 `GROUP BY ALL` 키 타입 검사를 제어합니다 |

**신규 기능**

| | |
|---|---|
| `DISTINCT` 디스크 스필 | `max_bytes_before_external_distinct`, `max_bytes_ratio_before_external_distinct`(0.5). 외부 집계·정렬과 마찬가지로 비율 기준 동작 |
| `REFRESH ... APPEND INCREMENTAL` | 갱신형 머티리얼라이즈드 뷰가 직전 갱신 이후 커밋된 행만 추가합니다. `Iceberg` 대상이면 정확히 한 번 — 커서를 스냅샷 요약 안에서 원자적으로 커밋 |
| `max_table_size_rows` / `_bytes_compressed` / `_bytes_uncompressed` | 테이블 총 크기를 제한하는 `MergeTree` 설정. `INSERT` 시작 시점과 병합 결과를 포함한 파트 커밋 시점에 검사하며, 레플리카 fetch에는 적용되지 않습니다 |
| `max_tables` 데이터베이스 설정 | `CREATE DATABASE d SETTINGS max_tables = 2` → `Code: 724. Too many tables`. 뷰와 딕셔너리도 포함해 셉니다 |
| `regr_slope`·`regr_intercept`·`regr_r2`·`regr_count`·`regr_avgx`·`regr_avgy`·`regr_sxx`·`regr_syy`·`regr_sxy` | SQL 표준 선형 회귀 집계 함수 |
| `JSON` 서브컬럼 대괄호 문법 | `json['a']['b']`, 중첩 `arrayElement`로 변환 |
| `system.statements` | SQL 문 문서 101행 — 이름·문법·설명·예제. 랩 04가 여기서 `CREATE TOKEN`을 읽습니다 |
| `system.session_query_ids` | 현재 세션의 쿼리 id를 실행 순서로. "방금 실행한 쿼리"를 찾는 데 클라이언트 측 `query_id`나 `log_comment`가 필요 없습니다. `session_query_ids_history_size`(1000)로 제한 |
| `arrayFlattenedLength` | 모든 중첩 수준의 원소를 셉니다 — `[[1,2],[3],[4,5,6]]`은 6, `length`는 3. PostgreSQL의 `cardinality`와 동일 |
| `parseISO8601Duration` | `'PT1H30M'` → 5400 |
| `DateTime` + `Time` 연산 | `toDateTime('2026-09-23 00:00:00') + toTime('01:30:00')` |
| `splitByRegexp`의 `extract` 인자 | `tokens(s, 'splitByRegexp', re, 1)`은 구분자로 쪼개는 대신 각 매치의 첫 캡처 그룹을 반환 |
| `skip_empty_columns_on_insert` | 타입 기본값만 든 컬럼을 저장하지 않는 옵트인 `MergeTree` 설정. `serialization_info_version = 'with_missing_columns'`가 필요하며, 롤링 업그레이드 중에는 구버전을 유지하세요 |
| `type_json_skip_null_typed_paths` | `JSON`의 `NULL` 타입 경로를 부재로 취급해 동적 경로와 동작을 맞춥니다 |
| jemalloc 단편화 프로파일러 | 백트레이스·수명·크기 클래스를 담은 `system.jemalloc_sampled_allocations`, 서버 웹 UI의 Fragmentation 탭 |
| `WORKLOAD`·`RESOURCE`의 `BACKUP`/`RESTORE` | SQL로 정의한 내용이 백업에 포함되고 복원 시 재생성됩니다. `ON CLUSTER`도 |
| `workload_admission_timeout_ms` | 워크로드 쿼리 슬롯 대기 시간을 제한. `0`은 기존의 무제한 대기 |
| `S3Queue` `mode = 'exclusive'` | Keeper 조율 없이 서버 메모리에서만 처리를 추적 — 단일 서버 고처리량 수집용 |
| `nats_ca_file` / `nats_client_cert_file` / `nats_client_key_file` | `NATS` 엔진의 사설 CA 검증과 클라이언트 인증서 인증 |
| 값 없는 `clickhouse-client --ssh-key-file` | `ssh`와 같은 방식으로 키를 찾습니다 — `ssh-agent` 포함 |
| Iceberg v3 `first_row_id` / `last_seq_num` | 가상 컬럼으로 노출되고 삽입 시 기록됩니다 |
| 리더 백프레셔용 `keeper` 4글자 명령 | 느린 Raft 멤버에 대한 |

> changelog에는 현재 연도를 반환하는 무인자 `year()`도 있습니다. 하지만
> 26.9.1.1629에는 **없습니다** — `SELECT year()`는 여전히 `toYear`로 해석되어
> `NUMBER_OF_ARGUMENTS_DOESNT_MATCH`로 실패합니다. 이후 빌드를 기다리세요.

**실험 기능**

| | |
|---|---|
| `/ui` 내장 SQL 콘솔 | HTTP 서버가 제공하는 ClickHouse Cloud 콘솔. 랩 컨테이너에서 200을 반환합니다. `/play`와는 다른 것입니다 |
| `TimeSeries`와 PromQL | `TimeSeries` 테이블의 `SELECT` 지원, 외부 샘플 컬럼을 `samples`로 개명, `METRICS`를 `METRIC FAMILIES`로 개명(구 이름은 별칭 유지), 기본 `LowCardinality` 시리즈 id로 PromQL 기하평균 1.16배 향상. PromQL에 `absent`·`count_values`·`sum_over_time`·`avg_over_time`·`count_over_time`·`present_over_time`·`absent_over_time`·`quantile_over_time`·`predict_linear`·`max_over_time`·`min_over_time` 추가. 엔진 자체는 [TimeSeries + PromQL 랩](../../../usecase/timeseries-promql-oss/) 참고 |
| Prometheus HTTP API | `/api/v1/metadata`, `/api/v1/labels`, `/api/v1/label/<name>/values`, `/api/v1/format_query` |
| `trino` 방언 | `enable_trino_dialect`로 Trino SQL을 변환 — `ARRAY[...]`, `TRY_CAST`, `UNNEST`, `ROW`, `FETCH`, `LIMIT` 앞의 `OFFSET`, 수백 개 함수 매핑 |
| `KQL` 재구현 | SQL 텍스트로 변환 후 재파싱하던 방식 대신 전용 렉서·파서. `contains`/`has`의 표현식 주입과 Kusto와 어긋나던 결과들을 고칩니다. 미지원 문법은 오역 대신 거부 |
| `DeltaLake` `CREATE TABLE` | `delta-kernel-rs`로 초기 커밋을 쓰거나, 기존 `_delta_log`에 붙거나, Unity 카탈로그에 등록. `allow_delta_lake_create_table` 필요, `PARTITION BY`는 아직 미지원. 쓰기는 정확한 캐스트로 오버플로 시 예외(`delta_lake_accurate_write_cast`) |
| `hierarchicalKMeans`, `assignCentroid` | IVF 방식 벡터 검색의 구성 요소 |
| 병렬 레플리카 | `parallel_replicas_plan_based`가 런타임 통계로 스스로 활성화할 수 있고, `RIGHT JOIN`과 `ORDER BY ... WITH FILL`을 지원하며, `parallel_replicas_allow_merge_tables`로 `Merge` 테이블을 읽습니다 |
| 분산 플랜 | `make_distributed_plan`이 `LIMIT` 충족 후 유휴 상위 스테이지를 중단하고, 워커 프래그먼트에서 `max_threads`를 지키며, 완료 스테이지당 최대 100 ms 유휴 대기를 없애고, `INTERSECT`/`EXCEPT`를 지원합니다 |
| 적응형 코덱 선택 | `enable_adaptive_codec_selection`이 전용 후보 코덱이 없는 컬럼(기본 코덱과 `NONE` 중 작은 쪽을 선택 — 압축 불가 데이터가 원본보다 커지지 않음), `Array`/`String` 크기와 널 맵을 포함한 모든 서브스트림, 그리고 float의 `ALP`까지 확장 |
| `silk` 파이버 런타임 | `enable_silk_runtime`. 지원하는 서브시스템이 I/O 대기에 OS 스레드를 점유하는 대신 파이버에서 작업을 실행합니다 |
| Cascades eager aggregation | `cascades_aggregation_pushdown`이 비용 기반 선택지로 부분 집계를 `JOIN` 아래로 내립니다 |

### 검증

네 개 `.sql` 파일의 모든 쿼리를 이 랩이 띄우는 컨테이너의 **26.9.1.1629**에서
실행했고, 위에 인용한 수치·플랜 조각·에러 코드는 전부 그 실행 결과입니다.
`04-create-token.sh`도 끝까지 실행했습니다.

작성 중 우회한 것이 둘 있고, 모두 SQL에 주석으로 남겼습니다.

- `UNION ALL`은 뒤따르는 `ORDER BY`에 컬럼 별칭을 노출하지 않습니다. 그래서
  랩 01·03·04의 비교 표는 정렬 전에 union을 감쌉니다. 26.8 랩이 부딪힌 것과
  같은 함정입니다.
- 거부된 로그인은 예외를 발생시키고, 그러면 `.sql` 파일이 그 줄에서 멈춥니다.
  그래서 랩 04는 `.sql`을 예외 없이 유지하고 `ACCESS_DENIED`·
  `AUTHENTICATION_FAILED` 실증은 연결을 하나씩 열어 `.sh` 러너에 두었습니다.

changelog의 주장 중 이 빌드에서 성립하지 않은 것이 하나 있고 위에 표시했습니다
— 무인자 `year()`입니다.

---

**Happy Learning! 🚀**

## License

[MIT](../../../LICENSE) — same as the rest of the repository.

## 라이선스

[MIT](../../../LICENSE) — 저장소 전체와 동일합니다.
