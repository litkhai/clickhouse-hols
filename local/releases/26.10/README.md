# ClickHouse 26.10

[English](#english) | [한국어](#한국어)

---

## English

**Released 2026-10-22 · verified here against 26.10.3.7**

26.10 is the largest release so far: 37 backward incompatible changes, 60 new
features, 41 experimental features and 225 performance improvements. The
announcement leads with a `Cluster` database engine, query cache on disk, a
columns cache, `LATERAL JOIN`, joins on arbitrary `ON` conditions, PromQL and
LogsQL, an Elasticsearch table function and an XGBoost dictionary.

This lab takes five that you can see working in a single container, and asks
of each what it actually does, not just whether it parses.

| Lab | Feature | Why it is here |
|-----|---------|----------------|
| [01](01-lateral-join.sql) | `LATERAL JOIN`, OUTER joins on any `ON` | Top-n per group in standard SQL, and the end of `INVALID_JOIN_ON_EXPRESSION` |
| [02](02-function-composition.sql) | Function composition, placeholders `_` / `_1`, Trino spellings, `SIMILAR TO` | The shortest lambda syntax ClickHouse has had, with one rule that bites |
| [03](03-in-set-spill.sql) | `IN` sets spill to disk | A large `IN (subquery)` under a memory cap now finishes — if you set the right threshold |
| [04](04-logsql.sql) | LogsQL dialect | VictoriaLogs queries over a ClickHouse table, and what the translation reads |
| [05](05-xgboost.sql) | XGBoost dictionary | A model trained at load time and served by a function |

### Quick start

```bash
./00-setup.sh                 # brings up ClickHouse 26.10 via local/oss-docker
./01-lateral-join.sh
./02-function-composition.sh
./03-in-set-spill.sh          # builds a 20-million-key set several times
./04-logsql.sh
./05-xgboost.sh
```

Each `NN-*.sh` pipes the matching `.sql` into `clickhouse-client`, then runs
the statements that are *supposed* to fail, one connection each. An error stops
a `.sql` file at that line, so every `.sql` here is exception-free and every
refusal lives in its `.sh`. Read the SQL — the comments are the lab.

Three labs use experimental settings: `allow_experimental_lateral_join` (01),
`enable_logsql_dialect` (04) and `enable_xgboost` (05). The block nested loop
join (01), composition (02) and `IN` spilling (03) are production tier.

---

### 01 · `LATERAL JOIN` and joins on arbitrary `ON` conditions

```sql
SET allow_experimental_lateral_join = 1;

SELECT c.name, t.id, t.amount
FROM customers AS c
LEFT JOIN LATERAL (
    SELECT id, amount FROM orders AS o
    WHERE o.customer_id = c.id          -- refers to the row on the left
    ORDER BY amount DESC
    LIMIT 2
) AS t ON true
SETTINGS join_use_nulls = 1;
```

`LATERAL` lets a subquery in `FROM` refer to the row on its left: the standard
spelling of "top n per group" and "an aggregate per row".

**It is not a per-row loop.** `EXPLAIN` shows the correlated predicate turned
into a join key (`customer_id <=> customer_id`) and `ORDER BY ... LIMIT 2`
turned into a `LimitBy` step labelled *"LIMIT BY for decorrelated correlated
subquery"*, under an ordinary hash join. The lab writes the same thing by hand
with `LIMIT 2 BY customer_id` and gets the same rows. `LATERAL` is the readable
spelling of something ClickHouse could already do, which is also why it scales
like a hash join and not like a loop.

**Set `join_use_nulls = 1`.** With the default `0`, the customer with no orders
comes back with order id `0` and amount `0.00` — a row that reads like a real
order. With `1` it is `NULL`. This is not specific to `LATERAL`, but `LEFT JOIN
LATERAL` is exactly where you look for the empty side.

**An aggregate subquery always returns a row.** `INNER JOIN LATERAL (SELECT
count() ...)` keeps the customer without orders, with `count = 0`. That is SQL,
not a bug: an aggregate with no `GROUP BY` produces one row from no input.

**What it refuses** (in `01-lateral-join.sh`):

| Form | Result on 26.10.3.7 |
|------|---------------------|
| `FROM a, LATERAL (...)` | `Code: 62` *LATERAL is not supported with COMMA JOIN* |
| `CROSS JOIN LATERAL (...)` | `Code: 62` *LATERAL is not supported with CROSS JOIN* |
| a subquery with no reference to the left side | `Code: 48` *must reference at least one column from the left side* |
| `LIMIT ... WITH TIES` inside | `Code: 48` *decorrelation does not support LIMIT ... WITH TIES* |

So the forms PostgreSQL users reach for first — the comma and `CROSS JOIN
LATERAL` — are the two that do not parse. Write `LEFT` or `INNER JOIN LATERAL
... ON true`.

**Arbitrary `ON` conditions.** The second half of the lab joins orders to a
table of overlapping price bands on `abs(amount - lo) < 10`. No column of one
side equals a column of the other, so there is no hash key. Which join runs
depends on the kind:

| Join | Condition | Algorithm (`query_log.used_join_algorithms`) |
|------|-----------|----------------------------------------------|
| `INNER` | `amount >= lo AND amount < hi` | `IE_JOIN` |
| `INNER` | `abs(amount - lo) < 10` | `CONSTANT` (a `CROSS` join and a filter) |
| `LEFT` | `o.customer_id = c.id` | `HASH` |
| `LEFT` | `abs(amount - lo) < 10` | `BlockNestedLoopJoin` in `EXPLAIN`; **`[]` in `query_log`** |

`INNER` joins on such conditions already worked before 26.10. What is new is
the `OUTER` case: on 26.9.11.2 a `LEFT` or `FULL` join without an equality
fails with `Code: 403 INVALID_JOIN_ON_EXPRESSION`. 26.10 runs it as a block nested
loop join — every left block against every right block, as costly as a
`CROSS JOIN` with a filter, so mind the size of both sides. Turning it off
(`allow_block_nested_loop_join = 0`) brings back the 403, now with a hint
naming the setting.

**The new `query_log` columns do not see the new join.** `used_join_algorithms`,
`used_join_kinds` and `used_number_of_joins` are new in 26.10 and record hash,
IE and cross joins correctly. For a block nested loop join they come back `[]`,
`[]` and `0` — reproduced at 20,000 × 20,000 rows. Until that changes, find
such queries by their plan, not by `query_log`.

---

### 02 · Function composition and placeholders

```sql
SELECT arrayMap(plus(_, 1) | multiply(_, 2), [1, 2, 3]);   -- [4, 6, 8]
SELECT arrayMap(_1 * 2 + 1, [1, 2, 3]);                     -- [3, 5, 7]
SELECT arrayMap(lower | reverse, ['AbC', 'XyZ']);           -- ['cba', 'zyx']
```

A placeholder turns an expression into a lambda; `|` chains two functions left
to right, so `f | g` is `g(f(x))`, the way a shell pipe reads. The analyzer
resolves both into an ordinary lambda — `EXPLAIN QUERY TREE` shows
`lambda(tuple(__composed_arg_1), multiply(plus(__composed_arg_1, 1), 2))` — so
there is no run-time cost and nothing a lambda could not already do.

**The rule that bites: every bare `_` is a new argument.** `_ * _` is
`(a, b) -> a * b`, not `x -> x * x`, and `arrayMap(_ * _, [1, 2, 3])` fails
with *must be a function with 1 arguments, found Function((?, ?) -> ?)*. Number
them to reuse one: `_1 * _1`. The two-argument reading is what you want in
`arrayFold(_1 + _2, arr, 0)`.

The other three rules, each shown as an error in the `.sh`:

- `SELECT 5 | 3` → `Code: 36`. `|` is composition only where a function is
  expected. For bitwise OR, `bitOr`.
- `arrayMap(toString | length, ...)` → `Code: 36`. A variadic function cannot
  be composed by name; write `toString(_)`.
- `arrayMap(plus(_, 1), [1]) FROM (SELECT 100 AS _)` → `Code: 43`. A column
  named `_` wins, and the "lambda" is a number.

That last one is the compatibility guarantee: `SELECT _ FROM (SELECT 1 AS _)`
and `arrayMap(_ -> _ + 1, ...)` still mean what they meant in 26.9.

**Other dialects, in plain ClickHouse SQL.** 26.9 accepted these only behind
`dialect = 'trino'`. 26.10 accepts them in the default dialect; on 26.9.11.2
every one fails (`Code: 62` or `Code: 46`):

| | |
|---|---|
| `TRY_CAST('abc' AS Int32)` | `NULL` instead of an exception |
| `ARRAY[1, 2, 3]` | array constructor |
| `starts_with`, `slice`, `regexp_like` | Trino names for existing functions |
| `SIMILAR TO` | the SQL-standard pattern predicate |

`SIMILAR TO` takes LIKE's `%` and `_` plus regex-style alternation and
grouping, matched against the **whole** string: `'bc' SIMILAR TO '(a|b)c'` is
true, `'abc' SIMILAR TO '(a|b)c'` is false.

---

### 03 · `IN` sets spill to disk

```sql
SELECT count() FROM numbers(2000000)
WHERE intHash64(number) IN (SELECT k FROM ids)       -- 20 million keys
SETTINGS max_memory_usage = 400000000,                -- 400 MB cap
         max_bytes_before_external_set = 100000000;   -- spill past 100 MB
```

`x IN (SELECT ...)` builds a hash set of the subquery before the outer query
reads a row. Until 26.10 the set had to fit in memory. Now it is written to
disk in parts past a threshold and merged back for the lookup. Measured with
20 million `UInt64` keys and 2 million probes:

| Run | Peak memory | `spilled_to_disk` | Result |
|-----|-------------|-------------------|--------|
| defaults, no cap | 768 MiB | `[]` | 2,000,000 |
| `max_bytes_before_external_set = 100 MB` | 155 MiB | `['set']` | 2,000,000 |
| 400 MB cap + 100 MB threshold | 156 MiB | `['set']` | 2,000,000 |
| `NOT IN`, 100 MB threshold | 158 MiB | `['set']` | 0 |
| 400 MB cap, spilling off (what 26.9 does) | — | — | `Code: 241 MEMORY_LIMIT_EXCEEDED` |
| **400 MB cap, defaults otherwise** | — | — | **`Code: 241`** |

Spilling cost 1.3 to 2 times the run time across the runs behind this table.
The profile events show what happened: 2 parts written, 1 merge, 250 MiB on
disk, about 7.4 million keys kept in memory as the tail.

**The last row is the one to remember.** The new default,
`max_bytes_ratio_before_external_set = 0.5`, is half of the memory available
under the **server or user** limit, calculated when the query starts. It does
not look at a per-query `max_memory_usage`. Here the server limit is 3.16 GiB,
so the ratio's threshold is about 1.6 GiB, far above a 400 MB cap: the query
hits the cap first and fails exactly as on 26.9. The changelog says so in one
clause; it is easy to read past. To spill under a per-query cap, set
`max_bytes_before_external_set` below it.

`GLOBAL IN` spills the same way (`['set']`, checked by hand). A `LEFT SEMI
JOIN` doing the same lookup does not — it is a join and fails under the same
cap with `Code: 241` in `FillingRightJoinSide`; joins have their own spill
settings.

On 26.9.11.2 neither setting exists, and the capped query fails at the same
point with the same code.

---

### 04 · The LogsQL dialect

```sql
SET enable_logsql_dialect = 1, logsql_table = 'logs', dialect = 'logsql';

level:error | stats by (host) count() as n | sort by (host);
"disk quota" | fields _time, host, _msg | sort by (_time) | limit 3;
_time:[2026-10-26T01:00:00Z, 2026-10-26T02:00:00Z) | count();
```

LogsQL, the query language of VictoriaLogs, is a filter followed by pipes.
26.10 translates it at parse time into a `SELECT` over one configured table,
whose time and message fields are the columns named by `logsql_time_column`
and `logsql_message_column` (`_time` and `_msg` by default). Everything in the
lab parses and returns the right answer: word, phrase, field, numeric, stream,
`i()` and substring filters, `stats by`, `sort`, `fields`, `limit`.

**What it reads is the finding.** Over 2 million rows with a text index on
`_msg`, with the query condition cache off so every run is a cold read:

```text
query                                 returned        read
_time:[01:00, 02:00) | fields _time      3,600       8,192
SQL: WHERE hasToken(_msg, 'quota')          20     163,840
quota | fields _time                        20   2,000,000
i(QUOTA) | fields _time                     20   2,000,000
*uota* | fields _time                       20   2,000,000
```

The time range prunes by the primary key. **Every text filter reads the whole
table**, text index or not, while the same word written as SQL `hasToken` reads
20 granules through the index. The reason is the translation. The lab recovers
it from the query condition cache's log line, since the translated `SELECT` is
not logged anywhere else. The word `quota` becomes:

```text
match(ifNull(toString(_msg), ''), '(?:^|[^0-9A-Za-z_\x80-\xFF])quota(?:$|[^0-9A-Za-z_\x80-\xFF])')
```

A regular expression over `toString` of the column: correct word-boundary
semantics, and nothing an index can answer.

So, on 26.10.3.7: put a `_time` range in every LogsQL query, and keep hot
lookups in SQL. Repeated LogsQL queries do get faster — the query condition
cache remembers which granules a predicate ruled out — which is why the lab
switches it off before measuring.

Two smaller things: in this dialect a `--` comment becomes part of the next
query's text in `query_log`, and the `format` pipe is LogsQL's, not
ClickHouse's `FORMAT` (`| format null` fails).

---

### 05 · XGBoost dictionaries

```sql
SET enable_xgboost = 1;

CREATE DICTIONARY late_model (distance_km Float64, items Float64, hour Float64, late Float64)
PRIMARY KEY (distance_km, items, hour)              -- the features, in order
SOURCE(CLICKHOUSE(DB 'xg' TABLE 'train'))           -- late is the one attribute: the target
LAYOUT(XGBOOST(objective 'binary:logistic' num_iterations 100 max_depth 4))
LIFETIME(0);

SELECT predictXGBoost('late_model', 12.5, 20, 18);   -- a probability
```

A dictionary that holds a model instead of rows. Loading it trains a
gradient-boosted model on the source table; `predictXGBoost` runs it.

The lab generates 50,000 deliveries with a known rule — late when the distance
and the basket are both large, or in the evening rush — and flips 5% of the
labels, which caps the best possible accuracy at about 0.95. Trained on 80% in
0.07 s, scored on the other 20%:

| | Accuracy | ROC AUC |
|---|---|---|
| XGBoost, 100 rounds, depth 4 | **0.9536** | 0.9343 |
| the rule that generated the data | 0.9536 | — |
| always "on time" | 0.6948 | — |

The model matches the true rule exactly on the held-out rows: it has learned
the rule and nothing of the noise.

**Trees do not extrapolate.** A regressor on `y = 2·x1 + 3·x2`, trained for
`x1` in [0, 99], predicts 8.00, 400.13 and 791.91 inside the range — and 791.91
again for `x1 = 1000`, where the truth is 8,000. Outside the training range a
tree model returns its largest leaf. Adding rows up to `x1 = 1099` and running
`SYSTEM RELOAD DICTIONARY` gives 7,984.52.

That reload is the whole lifecycle, and it is worth knowing before building on
this:

- **Training happens on every load**, including a server restart. The model is
  not persisted. `SYSTEM RELOAD DICTIONARY` retrains on the current rows; a
  non-zero `LIFETIME` retrains on a schedule.
- **The whole training set is in memory** while it trains.
- `system.dictionaries` shows `element_count = 0` and `bytes_allocated = 0`:
  there are no rows, and XGBoost does not report the model's memory.
- `dictGet` fails (`Code: 1 UNSUPPORTED_METHOD`); `predictXGBoost` is the only
  way in, and it needs `enable_xgboost = 1` on every query (`Code: 344`
  without).
- The layout's documentation marks it as not supported in ClickHouse Cloud.

---

### Also in 26.10, not covered by these labs

Where a row says *checked*, it was run on 26.10.3.7 in the lab container.
Everything else is from the changelog.

**Removals and breaking changes**

| | |
|---|---|
| **The old query analysis is gone, also for remote queries** | A server no longer uses it for a query another server sends. A cluster whose initiator is older than 26.10 gets the analyzer on 26.10 shards regardless, and can see `NOT_FOUND_COLUMN_IN_BLOCK`. Upgrade initiators last, or all at once |
| **`seccomp` filter on by default** | The packaged `config.xml` and the Docker image set `seccomp` to `trap`. A sandbox that refuses the `seccomp` system call needs `log` or `disabled` **before** the upgrade; executable UDFs may need it off. *Checked*: `trap` in `system.server_settings`, and the server starts under this repository's Docker seccomp profile |
| `system.metric_log` is bucketed by default | One `metrics Map(Enum16, Int64)` column with 128 buckets instead of thousands of columns. *Checked*: 12 real columns, and the 2,281 old names are `ALIAS metrics['...']`, so existing queries keep working |
| Settings constraints apply to SQL-defined users | A `GRANT`, `DROP ROLE` or `CREATE USER OR REPLACE` that would change a constrained setting indirectly is refused |
| `max_bytes_before_external_join` drives spilling for every hash join | Including `grace_hash`; `max_rows_in_join` / `max_bytes_in_join` are hard caps again |
| `arrayCount` returns `UInt64` | *Checked*. `array_count_legacy_uint32_result = 1` or `compatibility = '26.9'` restores `UInt32`; set it on upgraded shards during a rolling upgrade |
| `accurateCast` to `Nullable` throws | Instead of returning `NULL` for an unrepresentable value |
| `SELECT ... FINAL` on `SummingMergeTree` keeps all-zero rows | It used to drop them depending on which columns were read, so `count()` and `SELECT *` disagreed |
| `skip_unavailable_shards` with every shard skipped | Fails with `ALL_CONNECTION_TRIES_FAILED` instead of an empty result |
| `MATERIALIZED` columns follow `TTL` resets | Recomputed when the `TTL` resets their source column |
| JSON `null` into a non-`Nullable` number | Throws with `input_format_null_as_default = 0` instead of storing `0` |
| `arrayJoin` lowered to an `ARRAY JOIN` step | Streams instead of materializing; `runningDifference` and friends next to it now see the expansion's blocks |
| `ATTACH TABLE ... FROM` needs `FILE` grants | `READ ON FILE` and `WRITE ON FILE` on the source |
| Storage configuration is validated | An unknown element under a disk is `UNKNOWN_ELEMENT_IN_CONFIG` — a server with a typo there will not start |
| Zero-argument `year()` removed | The 26.9 lab noted that the changelog listed it but the build did not have it. *Checked*: still `Code: 42` here |
| `validate_mutation_query`, `enable_optimize_predicate_expression` and others | Obsolete; mutations are always validated |
| Experimental `ZXC` codec format changed | Data written with `CODEC(ZXC)` before 26.10 cannot be read |
| `Remote`, `RemoteSecure`, `Cluster` engines reject an empty database name | A server holding such a database does not start — drop them first |

**New features**

| | |
|---|---|
| **Hash tables use up to half the memory** | *Checked* against 26.9.11.2 in the same Docker VM (Apple silicon, 7.75 GiB, `max_threads = 8`, one run each): `GROUP BY` on 20 M `UInt64` keys 512.46 → 256.49 MiB, `uniqExact` over 20 M values 514.66 → 258.68 MiB, `GROUP BY` on 5 M `String` keys unchanged at 128.5 MiB. Wall time was 14–40% *higher* on 26.10 in these single runs — not a benchmark, but no speed-up on this setup either |
| `keyValuePairs` text index answers `IN` | *Checked*: `attrs['tenant'] IN ('t7', 't9')` reads 27/245 granules; on 26.9.11.2 it reads 245/245, the trap the 26.9 lab recorded. `mapContainsKeyValue(map, k, v)` is new and indexed too (13/245) |
| `Cluster` database engine | Real-time access to the tables of a configured cluster database, forwarding `SELECT` and `INSERT` |
| `Overlay` database engine | The union of the tables of several databases, each an `Alias` to the first source that has it |
| Query cache on disk | Entries in a filesystem cache: more room, survive restarts, shareable through a distributed cache. `query_cache_on_disk_cache_name` |
| `elasticsearch` table function | *Checked*: listed in `system.table_functions`; not exercised here |
| Workload scheduling and spilling | `scheduler` per workload (`fifo`, `fair`, `las`, `priority`), and `max_memory_before_spill` / `max_memory_to_spill_ratio` as a per-workload soft limit that makes `ORDER BY`, `GROUP BY`, `IN`, `DISTINCT` and grace-hash `JOIN` spill |
| Notebook mode in `/play` | A `[+]` under the result adds query or Markdown cells, restored on reload |
| `SQLite` format, `Freeform` input format | Read and write SQLite files; schema inference for arbitrary tabular text |
| `written_rows` quota resource | Limit `INSERT`ed rows, not only bytes |
| `query_log`: `used_join_*`, `spilled_to_disk` | Labs 01 and 03 use them — and lab 01 shows what they miss |
| `traceView` table function | An OpenTelemetry trace as a call tree with per-span timeline bars |
| `obfuscate` table function | Anonymized query results |
| `SIMILAR TO`, `sql_compatible_division_for_integers` | *Checked*: `-7 / 2 = -3` with the setting, truncating toward zero |
| New functions | *Checked*: `arrayMinIndex`, `arrayMaxIndex`, `arrayRemoveAt`, `mapRemove`, `mapEntries`, `normalizedQueryHashUnordered` (`SELECT a, b` and `SELECT b, a` hash the same), `encodeQuotedPrintable` / `decodeQuotedPrintable` |
| `-Map` over non-`Map` columns | *Checked*: `sumMap(v, k)` |
| `avg`, `sum` over `Interval` | *Checked*: `avg(toIntervalSecond(n))` is `IntervalSecond` |
| `MATERIALIZED` CTEs in recursive `WITH` | Evaluated once, read by every step |
| `BACKUP ... EXCEPT DATA FROM TABLE` | Definition without rows |
| `FileLog` globs and `SYSTEM RESET FILELOG` | Re-read files without recreating the table |
| `clickhouse-client --login` with any OIDC provider | Endpoint discovery, device-code flow |
| `Parquet` `VARIANT`, Iceberg `variant` | Read into `Dynamic` / `JSON` |
| `generateRandom` for `JSON`, `Dynamic`, `Variant`, `Time` | With realistic generated JSON schemas |

**Experimental**

| | |
|---|---|
| Columns cache | `use_columns_cache`: deserialized columns of wide parts kept in memory per granule stripe, cheaper than the uncompressed cache. *Checked*: setting present, tier Experimental |
| PromQL | The announcement quotes 100% basic and 93% extended compatibility. New range functions (`stddev_over_time`, `mad_over_time`, ...), `timestamp`, `step`, `range`, stale markers, and many fixes. See the [TimeSeries + PromQL lab](../../../usecase/timeseries-promql-oss/) |
| `PCO` codec | `enable_pco_codec`, for fixed-width numbers |
| Unity Catalog v2 | One catalog for `DeltaLake` and `Iceberg` tables, `use_unity_catalog_v2` |
| Embedded Iceberg REST catalog | Namespaces in memory or Keeper, metadata in S3 |
| `ipcrypt*` functions | Format-preserving IP encryption, deterministic or prefix-preserving |
| Iceberg v3 deletion vectors, `DROP PARTITION` | Read support; drop on standalone tables and REST catalogs |
| Distributed plans | Join runtime filters across stages, compression of exchanged data, trace propagation to workers |

### Verified

Every query in the five `.sql` files was run against **26.10.3.7**
(`clickhouse/clickhouse-server:26.10`, pulled 2026-10-28) with
`tools/hol run local/releases/26.10` — five PASS — and every `NN-*.sh` was run
end to end against a `clickhouse-26-10` container started with this
repository's seccomp profile. Every number, plan fragment and error code above
is from those runs. The 26.9 comparisons ran on 26.9.11.2, the `26.9` image
already on the machine.

`00-setup.sh` was then run as a reader would, bringing up `clickhouse-26-10`
through `local/oss-docker`, and all five `NN-*.sh` were run against it again
with the same results. Its last check prints *Could not verify version* even
though the server is up: it looks for a version string in the reply to `/`,
which is `Ok.`. The 26.9 script has the same check; `./01-lateral-join.sh`
working is the real confirmation.

Three things were worked around while writing, all noted in the SQL:

- An error stops a `.sql` file at that line, so every refusal is in the `.sh`
  runners, one connection each — the same split the 26.9 lab used for lab 04.
- The query condition cache makes a repeated filter read fewer rows than a cold
  one. The first LogsQL measurements were taken with it on and looked as if the
  text index were used; lab 04 measures with `use_query_condition_cache = 0`.
- `query_log` keeps every run, so the comparison queries take the latest row
  per `log_comment` with `LIMIT 1 BY`, and re-running a lab does not pile up
  rows.

Two observations disagree with what the changelog leads you to expect, and are
flagged above: block nested loop joins are missing from the new `query_log`
join columns (lab 01), and LogsQL text filters do not reach a text index
(lab 04).

---

## 한국어

**2026-10-22 릴리스 · 여기서는 26.10.3.7로 검증**

26.10은 지금까지 가장 큰 릴리스입니다 — 하위 호환성 변경 37개, 신기능 60개,
실험 기능 41개, 성능 개선 225개. 발표는 `Cluster` 데이터베이스 엔진, 디스크
쿼리 캐시, 컬럼 캐시, `LATERAL JOIN`, 임의 `ON` 조건 조인, PromQL과 LogsQL,
Elasticsearch 테이블 함수, XGBoost 딕셔너리를 앞세웁니다.

이 랩은 그중 **컨테이너 하나에서 눈으로 확인할 수 있는** 다섯 가지를 골라,
파싱되는지가 아니라 실제로 무엇을 하는지를 묻습니다.

| 랩 | 기능 | 선정 이유 |
|----|------|-----------|
| [01](01-lateral-join.sql) | `LATERAL JOIN`, 임의 `ON`의 OUTER 조인 | 표준 SQL로 쓰는 그룹별 상위 n개, 그리고 `INVALID_JOIN_ON_EXPRESSION`의 끝 |
| [02](02-function-composition.sql) | 함수 합성, 플레이스홀더 `_` / `_1`, Trino 표기, `SIMILAR TO` | ClickHouse에서 가장 짧은 람다 문법. 단, 물리는 규칙이 하나 있음 |
| [03](03-in-set-spill.sql) | `IN` 집합의 디스크 스필 | 메모리 상한 아래의 큰 `IN (subquery)`가 이제 끝까지 돈다 — 임계값을 맞게 설정하면 |
| [04](04-logsql.sql) | LogsQL 방언 | ClickHouse 테이블 위의 VictoriaLogs 쿼리, 그리고 번역 결과가 실제로 읽는 양 |
| [05](05-xgboost.sql) | XGBoost 딕셔너리 | 로드 시점에 학습하고 함수로 서빙하는 모델 |

### 빠른 시작

```bash
./00-setup.sh                 # local/oss-docker으로 26.10 기동
./01-lateral-join.sh
./02-function-composition.sh
./03-in-set-spill.sh          # 2,000만 키 집합을 여러 번 만듭니다
./04-logsql.sh
./05-xgboost.sh
```

각 `NN-*.sh`는 같은 이름의 `.sql`을 `clickhouse-client`에 넘긴 뒤, **실패해야
하는** 문장을 연결 하나씩 실행합니다. 에러는 `.sql` 파일을 그 줄에서 멈추므로
여기의 `.sql`은 모두 예외가 없고, 거부 사례는 전부 `.sh`에 있습니다. SQL을
읽으세요 — 주석이 곧 랩입니다.

실험 설정을 쓰는 랩은 세 개입니다: `allow_experimental_lateral_join`(01),
`enable_logsql_dialect`(04), `enable_xgboost`(05). 블록 중첩 루프
조인(01), 함수 합성(02), `IN` 스필(03)은 production 등급입니다.

---

### 01 · `LATERAL JOIN`과 임의 `ON` 조건 조인

```sql
SET allow_experimental_lateral_join = 1;

SELECT c.name, t.id, t.amount
FROM customers AS c
LEFT JOIN LATERAL (
    SELECT id, amount FROM orders AS o
    WHERE o.customer_id = c.id          -- 왼쪽 행을 참조
    ORDER BY amount DESC
    LIMIT 2
) AS t ON true
SETTINGS join_use_nulls = 1;
```

`LATERAL`은 `FROM`의 서브쿼리가 왼쪽 행을 참조하게 합니다. "그룹별 상위 n개"와
"행마다 집계"의 표준 표기입니다.

**행마다 도는 루프가 아닙니다.** `EXPLAIN`을 보면 상관 조건은 조인 키
(`customer_id <=> customer_id`)가 되고, `ORDER BY ... LIMIT 2`는 *"LIMIT BY for
decorrelated correlated subquery"*라는 `LimitBy` 단계가 되어 평범한 해시 조인
아래에 놓입니다. 랩은 같은 것을 `LIMIT 2 BY customer_id`로 손수 쓰고 같은 행을
얻습니다. `LATERAL`은 ClickHouse가 이미 할 수 있던 일을 읽기 좋게 쓰는
방법이고, 그래서 루프가 아니라 해시 조인처럼 확장됩니다.

**`join_use_nulls = 1`을 설정하세요.** 기본값 `0`이면 주문이 없는 고객이 주문
id `0`, 금액 `0.00`으로 돌아옵니다 — 진짜 주문처럼 보이는 행입니다. `1`이면
`NULL`입니다. `LATERAL`만의 문제는 아니지만, `LEFT JOIN LATERAL`은 바로 빈
쪽을 확인하려고 쓰는 구문입니다.

**집계 서브쿼리는 항상 한 행을 돌려줍니다.** `INNER JOIN LATERAL (SELECT
count() ...)`은 주문 없는 고객을 `count = 0`으로 남깁니다. 버그가 아니라
SQL입니다 — `GROUP BY` 없는 집계는 입력이 없어도 한 행을 만듭니다.

**거부하는 것** (`01-lateral-join.sh`):

| 형태 | 26.10.3.7 결과 |
|------|----------------|
| `FROM a, LATERAL (...)` | `Code: 62` *LATERAL is not supported with COMMA JOIN* |
| `CROSS JOIN LATERAL (...)` | `Code: 62` *LATERAL is not supported with CROSS JOIN* |
| 왼쪽을 참조하지 않는 서브쿼리 | `Code: 48` *must reference at least one column from the left side* |
| 안쪽의 `LIMIT ... WITH TIES` | `Code: 48` *decorrelation does not support LIMIT ... WITH TIES* |

PostgreSQL 사용자가 먼저 쓰는 형태 — 콤마와 `CROSS JOIN LATERAL` — 가 정확히
파싱되지 않는 두 가지입니다. `LEFT` 또는 `INNER JOIN LATERAL ... ON true`로
쓰세요.

**임의 `ON` 조건.** 랩 후반은 주문을 서로 겹치는 가격대 테이블에
`abs(amount - lo) < 10`으로 조인합니다. 한쪽 컬럼이 다른 쪽 컬럼과 같다는
조건이 없으니 해시 키가 없습니다. 어떤 조인이 도는지는 종류에 따라 다릅니다.

| 조인 | 조건 | 알고리즘 (`query_log.used_join_algorithms`) |
|------|------|---------------------------------------------|
| `INNER` | `amount >= lo AND amount < hi` | `IE_JOIN` |
| `INNER` | `abs(amount - lo) < 10` | `CONSTANT` (`CROSS` 조인 + 필터) |
| `LEFT` | `o.customer_id = c.id` | `HASH` |
| `LEFT` | `abs(amount - lo) < 10` | `EXPLAIN`에는 `BlockNestedLoopJoin`, **`query_log`에는 `[]`** |

이런 조건의 `INNER` 조인은 26.10 이전에도 됐습니다. 새로운 것은 `OUTER`
쪽입니다. 26.9.11.2에서는 등호 없는 `LEFT`·`FULL` 조인이 `Code: 403
INVALID_JOIN_ON_EXPRESSION`으로 실패합니다. 26.10은 이를 블록 중첩 루프
조인으로 실행합니다 — 왼쪽 블록마다 오른쪽 블록 전부와 비교하므로 필터를 단
`CROSS JOIN`만큼 비쌉니다. 양쪽 크기를 보세요. 끄면
(`allow_block_nested_loop_join = 0`) 403이 돌아오고, 이제 설정 이름을 알려
주는 힌트가 붙습니다.

**새 `query_log` 컬럼이 새 조인을 보지 못합니다.** `used_join_algorithms`,
`used_join_kinds`, `used_number_of_joins`는 26.10에 새로 생겼고 해시·IE·크로스
조인은 제대로 기록합니다. 블록 중첩 루프 조인에서는 `[]`, `[]`, `0`이
나옵니다 — 20,000 × 20,000 행에서도 재현했습니다. 바뀌기 전까지 이런 쿼리는
`query_log`가 아니라 플랜으로 찾으세요.

---

### 02 · 함수 합성과 플레이스홀더

```sql
SELECT arrayMap(plus(_, 1) | multiply(_, 2), [1, 2, 3]);   -- [4, 6, 8]
SELECT arrayMap(_1 * 2 + 1, [1, 2, 3]);                     -- [3, 5, 7]
SELECT arrayMap(lower | reverse, ['AbC', 'XyZ']);           -- ['cba', 'zyx']
```

플레이스홀더는 식을 람다로 바꾸고, `|`는 두 함수를 왼쪽에서 오른쪽으로
잇습니다. `f | g`는 `g(f(x))`로, 셸 파이프처럼 읽힙니다. 애널라이저가 둘 다
평범한 람다로 풀어 씁니다 — `EXPLAIN QUERY TREE`에
`lambda(tuple(__composed_arg_1), multiply(plus(__composed_arg_1, 1), 2))`가
보입니다. 실행 비용은 없고, 람다로 못 하던 일이 생긴 것도 아닙니다.

**물리는 규칙: 맨 `_` 하나하나가 새 인자입니다.** `_ * _`는 `x -> x * x`가
아니라 `(a, b) -> a * b`이고, `arrayMap(_ * _, [1, 2, 3])`은 *must be a
function with 1 arguments, found Function((?, ?) -> ?)*로 실패합니다. 하나를
다시 쓰려면 번호를 붙이세요: `_1 * _1`. 두 인자로 읽히는 것이 바로 원하는
경우는 `arrayFold(_1 + _2, arr, 0)`입니다.

나머지 세 규칙은 `.sh`에서 에러로 보여 줍니다.

- `SELECT 5 | 3` → `Code: 36`. `|`는 함수가 올 자리에서만 합성입니다. 비트
  OR은 `bitOr`.
- `arrayMap(toString | length, ...)` → `Code: 36`. 가변 인자 함수는 이름으로
  합성할 수 없습니다. `toString(_)`로 쓰세요.
- `arrayMap(plus(_, 1), [1]) FROM (SELECT 100 AS _)` → `Code: 43`. `_`라는
  컬럼이 이기고, "람다"는 숫자가 됩니다.

마지막 것이 호환성 보장입니다. `SELECT _ FROM (SELECT 1 AS _)`와
`arrayMap(_ -> _ + 1, ...)`은 26.9에서와 같은 뜻입니다.

**다른 방언의 표기를 기본 ClickHouse SQL에서.** 26.9는 이것들을
`dialect = 'trino'`에서만 받았습니다. 26.10은 기본 방언에서 받고, 26.9.11.2에서는
모두 실패합니다(`Code: 62` 또는 `Code: 46`).

| | |
|---|---|
| `TRY_CAST('abc' AS Int32)` | 예외 대신 `NULL` |
| `ARRAY[1, 2, 3]` | 배열 생성자 |
| `starts_with`, `slice`, `regexp_like` | 기존 함수의 Trino 이름 |
| `SIMILAR TO` | SQL 표준 패턴 술어 |

`SIMILAR TO`는 LIKE의 `%`·`_`에 정규식식 선택과 그룹을 더한 것이고, **문자열
전체**와 비교합니다. `'bc' SIMILAR TO '(a|b)c'`는 참, `'abc' SIMILAR TO
'(a|b)c'`는 거짓입니다.

---

### 03 · `IN` 집합의 디스크 스필

```sql
SELECT count() FROM numbers(2000000)
WHERE intHash64(number) IN (SELECT k FROM ids)       -- 키 2,000만 개
SETTINGS max_memory_usage = 400000000,                -- 상한 400 MB
         max_bytes_before_external_set = 100000000;   -- 100 MB를 넘으면 스필
```

`x IN (SELECT ...)`는 바깥 쿼리가 한 행을 읽기 전에 서브쿼리 결과로 해시 집합을
만듭니다. 26.10 전에는 이 집합이 메모리에 다 들어가야 했습니다. 이제는 임계값을
넘으면 조각으로 디스크에 쓰고, 조회할 때 병합해 읽습니다. `UInt64` 키
2,000만 개와 조회 200만 건으로 측정한 결과입니다.

| 실행 | 최대 메모리 | `spilled_to_disk` | 결과 |
|------|-------------|-------------------|------|
| 기본값, 상한 없음 | 768 MiB | `[]` | 2,000,000 |
| `max_bytes_before_external_set = 100 MB` | 155 MiB | `['set']` | 2,000,000 |
| 상한 400 MB + 임계값 100 MB | 156 MiB | `['set']` | 2,000,000 |
| `NOT IN`, 임계값 100 MB | 158 MiB | `['set']` | 0 |
| 상한 400 MB, 스필 끔 (26.9와 같음) | — | — | `Code: 241 MEMORY_LIMIT_EXCEEDED` |
| **상한 400 MB, 나머지는 기본값** | — | — | **`Code: 241`** |

이 표를 만든 실행들에서 스필은 실행 시간을 1.3~2배로 늘렸습니다. 프로파일
이벤트로 보면 조각 2개를 쓰고, 병합 1번, 디스크 250 MiB, 꼬리로 메모리에 남긴
키 약 740만 개입니다.

**기억할 것은 마지막 행입니다.** 새 기본값
`max_bytes_ratio_before_external_set = 0.5`는 **서버 또는 사용자** 한도 아래
사용 가능한 메모리의 절반이고, 쿼리 시작 시점에 계산합니다. 쿼리별
`max_memory_usage`는 보지 않습니다. 여기서 서버 한도는 3.16 GiB이므로 비율
임계값은 약 1.6 GiB — 400 MB 상한보다 훨씬 위입니다. 쿼리는 상한에 먼저
닿아 26.9와 똑같이 실패합니다. changelog에는 한 구절로 적혀 있어 지나치기
쉽습니다. 쿼리별 상한 아래에서 스필하려면 `max_bytes_before_external_set`을
그보다 낮게 두세요.

`GLOBAL IN`도 같은 방식으로 스필합니다(`['set']`, 손으로 확인). 같은 조회를
하는 `LEFT SEMI JOIN`은 스필하지 않습니다 — 조인이므로 같은 상한에서
`FillingRightJoinSide`의 `Code: 241`로 실패합니다. 조인은 자기 스필 설정이
따로 있습니다.

26.9.11.2에는 두 설정 모두 없고, 상한을 건 쿼리는 같은 지점에서 같은 코드로
실패합니다.

---

### 04 · LogsQL 방언

```sql
SET enable_logsql_dialect = 1, logsql_table = 'logs', dialect = 'logsql';

level:error | stats by (host) count() as n | sort by (host);
"disk quota" | fields _time, host, _msg | sort by (_time) | limit 3;
_time:[2026-10-26T01:00:00Z, 2026-10-26T02:00:00Z) | count();
```

VictoriaLogs의 쿼리 언어 LogsQL은 필터 뒤에 파이프가 이어지는 형태입니다.
26.10은 이를 파싱 시점에 설정된 테이블 하나에 대한 `SELECT`로 번역합니다.
시간·메시지 필드는 `logsql_time_column`·`logsql_message_column`이 가리키는
컬럼(기본 `_time`, `_msg`)입니다. 랩의 모든 쿼리가 파싱되고 맞는 답을 냅니다
— 단어·구문·필드·숫자·스트림·`i()`·부분 문자열 필터, `stats by`, `sort`,
`fields`, `limit`.

**발견은 읽는 양에 있습니다.** `_msg`에 텍스트 인덱스가 있는 200만 행에서,
매번 콜드 읽기가 되도록 쿼리 조건 캐시를 끄고 측정했습니다.

```text
query                                 returned        read
_time:[01:00, 02:00) | fields _time      3,600       8,192
SQL: WHERE hasToken(_msg, 'quota')          20     163,840
quota | fields _time                        20   2,000,000
i(QUOTA) | fields _time                     20   2,000,000
*uota* | fields _time                       20   2,000,000
```

시간 범위는 기본 키로 가지치기됩니다. **텍스트 필터는 인덱스가 있든 없든 전부
테이블 전체를 읽고**, 같은 단어를 SQL `hasToken`으로 쓰면 인덱스로 그래뉼
20개만 읽습니다. 이유는 번역에 있습니다. 번역된 `SELECT`는 어디에도 기록되지
않아서, 랩은 쿼리 조건 캐시의 로그 줄에서 그것을 되찾습니다. 단어 `quota`는
이렇게 됩니다.

```text
match(ifNull(toString(_msg), ''), '(?:^|[^0-9A-Za-z_\x80-\xFF])quota(?:$|[^0-9A-Za-z_\x80-\xFF])')
```

컬럼의 `toString`에 대한 정규식입니다. 단어 경계 의미는 정확하지만, 어떤
인덱스도 답할 수 없는 형태입니다.

그러니 26.10.3.7에서는 모든 LogsQL 쿼리에 `_time` 범위를 넣고, 자주 도는 조회는
SQL로 두세요. LogsQL 쿼리를 반복하면 빨라지기는 합니다 — 쿼리 조건 캐시가 그
조건으로 걸러낸 그래뉼을 기억하기 때문이고, 랩이 측정 전에 캐시를 끄는 이유도
그것입니다.

작은 것 둘: 이 방언에서 `--` 주석은 `query_log`에서 다음 쿼리 텍스트의 일부가
되고, `format` 파이프는 ClickHouse의 `FORMAT`이 아니라 LogsQL의 것입니다
(`| format null`은 실패).

---

### 05 · XGBoost 딕셔너리

```sql
SET enable_xgboost = 1;

CREATE DICTIONARY late_model (distance_km Float64, items Float64, hour Float64, late Float64)
PRIMARY KEY (distance_km, items, hour)              -- 특성, 이 순서대로
SOURCE(CLICKHOUSE(DB 'xg' TABLE 'train'))           -- 유일한 속성 late가 목표값
LAYOUT(XGBOOST(objective 'binary:logistic' num_iterations 100 max_depth 4))
LIFETIME(0);

SELECT predictXGBoost('late_model', 12.5, 20, 18);   -- 확률
```

행 대신 모델을 담는 딕셔너리입니다. 로드하면 소스 테이블로 그래디언트
부스팅 모델을 학습하고, `predictXGBoost`가 그 모델을 실행합니다.

랩은 규칙이 알려진 배송 5만 건을 만듭니다 — 거리와 장바구니가 둘 다 크거나
저녁 혼잡 시간이면 지연 — 그리고 레이블 5%를 뒤집어, 가능한 최고 정확도를
약 0.95로 묶습니다. 80%로 0.07초에 학습하고 나머지 20%로 평가했습니다.

| | 정확도 | ROC AUC |
|---|---|---|
| XGBoost, 100 라운드, 깊이 4 | **0.9536** | 0.9343 |
| 데이터를 만든 규칙 | 0.9536 | — |
| 항상 "정시" | 0.6948 | — |

모델은 보류한 행에서 진짜 규칙과 정확히 일치합니다. 규칙을 배웠고 잡음은
하나도 배우지 않았습니다.

**트리는 외삽하지 않습니다.** `x1`이 [0, 99]인 데이터로 `y = 2·x1 + 3·x2`를
학습한 회귀 모델은 범위 안에서 8.00, 400.13, 791.91을 예측하고 — `x1 = 1000`
에서도 791.91을 냅니다. 정답은 8,000입니다. 학습 범위 밖에서 트리 모델은 가장
큰 리프 값을 돌려줍니다. `x1 = 1099`까지 행을 추가하고 `SYSTEM RELOAD
DICTIONARY`를 실행하면 7,984.52가 나옵니다.

그 리로드가 생명주기 전부이고, 이 위에 무언가를 만들기 전에 알아 둘 만합니다.

- **학습은 로드할 때마다** 일어납니다. 서버 재시작 포함. 모델은 저장되지
  않습니다. `SYSTEM RELOAD DICTIONARY`는 현재 행으로 다시 학습하고, 0이 아닌
  `LIFETIME`은 주기적으로 다시 학습합니다.
- 학습하는 동안 **학습 데이터 전체가 메모리에** 있습니다.
- `system.dictionaries`는 `element_count = 0`, `bytes_allocated = 0`을
  보여 줍니다. 행이 없고, XGBoost가 모델 메모리를 보고하지 않습니다.
- `dictGet`은 실패하고(`Code: 1 UNSUPPORTED_METHOD`), 들어가는 길은
  `predictXGBoost`뿐이며, 매 쿼리에 `enable_xgboost = 1`이 필요합니다(없으면
  `Code: 344`).
- 레이아웃 문서는 ClickHouse Cloud에서 지원하지 않는다고 표시합니다.

---

### 26.10의 다른 변화 (이 랩에서 다루지 않음)

*확인*이라고 적힌 행은 랩 컨테이너의 26.10.3.7에서 실행했습니다. 나머지는
changelog 내용입니다.

**제거와 호환성 변경**

| | |
|---|---|
| **이전 쿼리 분석이 원격 쿼리에서도 사라짐** | 다른 서버가 보낸 쿼리에도 더 이상 쓰지 않습니다. 이니시에이터가 26.10보다 오래된 클러스터는 26.10 샤드에서 무조건 애널라이저를 쓰게 되고 `NOT_FOUND_COLUMN_IN_BLOCK`을 볼 수 있습니다. 이니시에이터를 마지막에, 또는 한꺼번에 업그레이드하세요 |
| **`seccomp` 필터 기본 활성** | 패키지의 `config.xml`과 Docker 이미지가 `seccomp`을 `trap`으로 둡니다. `seccomp` 시스템 콜을 거부하는 샌드박스는 업그레이드 **전에** `log` 또는 `disabled`로 바꿔야 하고, 실행형 UDF는 꺼야 할 수 있습니다. *확인*: `system.server_settings`에 `trap`, 이 저장소의 Docker seccomp 프로필로 서버가 기동함 |
| `system.metric_log` 기본이 bucketed | 수천 개 컬럼 대신 버킷 128개짜리 `metrics Map(Enum16, Int64)` 컬럼 하나. *확인*: 실제 컬럼 12개, 기존 이름 2,281개는 `ALIAS metrics['...']`라 기존 쿼리는 그대로 동작 |
| SQL로 정의한 사용자에게도 설정 제약 적용 | 제약된 설정을 간접적으로 바꾸는 `GRANT`·`DROP ROLE`·`CREATE USER OR REPLACE`는 거부 |
| 모든 해시 조인의 스필 기준이 `max_bytes_before_external_join` | `grace_hash` 포함. `max_rows_in_join`·`max_bytes_in_join`은 다시 하드 상한 |
| `arrayCount`가 `UInt64` 반환 | *확인*. `array_count_legacy_uint32_result = 1` 또는 `compatibility = '26.9'`로 `UInt32` 복원. 롤링 업그레이드 중에는 업그레이드된 샤드에 설정 |
| `Nullable`로의 `accurateCast`가 예외 | 표현할 수 없는 값에 `NULL`을 돌려주던 동작 대신 |
| `SummingMergeTree`의 `SELECT ... FINAL`이 전부 0인 행을 유지 | 읽은 컬럼에 따라 지워져서 `count()`와 `SELECT *`가 달랐음 |
| 모든 샤드를 건너뛴 `skip_unavailable_shards` | 빈 결과 대신 `ALL_CONNECTION_TRIES_FAILED` |
| `MATERIALIZED` 컬럼이 `TTL` 리셋을 따름 | 원본 컬럼이 `TTL`로 리셋되면 다시 계산 |
| 비-`Nullable` 숫자에 JSON `null` | `input_format_null_as_default = 0`이면 `0` 저장 대신 예외 |
| `arrayJoin`이 `ARRAY JOIN` 단계로 내려감 | 물질화 대신 스트리밍. 옆의 `runningDifference` 등은 확장된 블록을 봄 |
| `ATTACH TABLE ... FROM`에 `FILE` 권한 필요 | 원본에 `READ ON FILE`과 `WRITE ON FILE` |
| 스토리지 설정 검증 | 디스크 아래 모르는 요소는 `UNKNOWN_ELEMENT_IN_CONFIG` — 오타가 있으면 서버가 안 뜸 |
| 무인자 `year()` 제거 | 26.9 랩은 changelog에 있지만 빌드에 없다고 기록했습니다. *확인*: 여기서도 여전히 `Code: 42` |
| `validate_mutation_query`, `enable_optimize_predicate_expression` 등 | 폐기. 뮤테이션은 항상 검증 |
| 실험 코덱 `ZXC` 형식 변경 | 26.10 전에 `CODEC(ZXC)`로 쓴 데이터는 읽을 수 없음 |
| `Remote`·`RemoteSecure`·`Cluster` 엔진이 빈 데이터베이스 이름 거부 | 그런 데이터베이스가 있으면 서버가 안 뜸 — 먼저 삭제 |

**신기능**

| | |
|---|---|
| **해시 테이블 메모리 최대 절반** | 같은 Docker VM(Apple silicon, 7.75 GiB, `max_threads = 8`, 각 1회)에서 26.9.11.2와 *확인*: `UInt64` 키 2,000만 개 `GROUP BY` 512.46 → 256.49 MiB, 값 2,000만 개 `uniqExact` 514.66 → 258.68 MiB, `String` 키 500만 개 `GROUP BY`는 128.5 MiB로 변화 없음. 소요 시간은 이 1회 실행들에서 26.10이 14~40% *더 길었음* — 벤치마크는 아니지만, 이 환경에서 빨라지지도 않음 |
| `keyValuePairs` 텍스트 인덱스가 `IN`에 응답 | *확인*: `attrs['tenant'] IN ('t7', 't9')`가 그래뉼 27/245를 읽음. 26.9.11.2는 245/245 — 26.9 랩이 기록한 함정. 새 함수 `mapContainsKeyValue(map, k, v)`도 인덱스를 탐(13/245) |
| `Cluster` 데이터베이스 엔진 | 설정된 클러스터 데이터베이스의 테이블에 실시간 접근, `SELECT`·`INSERT` 전달 |
| `Overlay` 데이터베이스 엔진 | 여러 데이터베이스 테이블의 합집합. 각 테이블은 그것을 가진 첫 원본의 `Alias` |
| 디스크 쿼리 캐시 | 파일시스템 캐시에 항목 저장: 공간이 크고, 재시작 후에도 남고, 분산 캐시로 공유 가능. `query_cache_on_disk_cache_name` |
| `elasticsearch` 테이블 함수 | *확인*: `system.table_functions`에 있음. 여기서 실행하지는 않음 |
| 워크로드 스케줄링과 스필 | 워크로드별 `scheduler`(`fifo`, `fair`, `las`, `priority`), 그리고 `ORDER BY`·`GROUP BY`·`IN`·`DISTINCT`·grace-hash `JOIN`을 스필시키는 워크로드별 소프트 한도 `max_memory_before_spill`·`max_memory_to_spill_ratio` |
| `/play` 노트북 모드 | 결과 아래 `[+]`로 쿼리·Markdown 셀 추가, 새로 고쳐도 복원 |
| `SQLite` 형식, `Freeform` 입력 형식 | SQLite 파일 읽기·쓰기, 임의 표 형식 텍스트의 스키마 추론 |
| `written_rows` 쿼터 자원 | 바이트뿐 아니라 `INSERT`한 행 수 제한 |
| `query_log`: `used_join_*`, `spilled_to_disk` | 랩 01·03이 사용 — 그리고 랩 01은 무엇을 놓치는지 보여 줌 |
| `traceView` 테이블 함수 | OpenTelemetry 트레이스를 span별 타임라인 막대가 있는 호출 트리로 |
| `obfuscate` 테이블 함수 | 익명화된 쿼리 결과 |
| `SIMILAR TO`, `sql_compatible_division_for_integers` | *확인*: 설정을 켜면 `-7 / 2 = -3`, 0 쪽으로 버림 |
| 새 함수 | *확인*: `arrayMinIndex`, `arrayMaxIndex`, `arrayRemoveAt`, `mapRemove`, `mapEntries`, `normalizedQueryHashUnordered`(`SELECT a, b`와 `SELECT b, a`가 같은 해시), `encodeQuotedPrintable`·`decodeQuotedPrintable` |
| 비-`Map` 컬럼에 `-Map` | *확인*: `sumMap(v, k)` |
| `Interval`에 `avg`·`sum` | *확인*: `avg(toIntervalSecond(n))`의 타입은 `IntervalSecond` |
| 재귀 `WITH` 안의 `MATERIALIZED` CTE | 한 번 계산하고 모든 단계가 읽음 |
| `BACKUP ... EXCEPT DATA FROM TABLE` | 행 없이 정의만 |
| `FileLog` 글롭과 `SYSTEM RESET FILELOG` | 테이블을 다시 만들지 않고 파일 재읽기 |
| 임의 OIDC 공급자로 `clickhouse-client --login` | 엔드포인트 탐색, device-code 흐름 |
| `Parquet` `VARIANT`, Iceberg `variant` | `Dynamic`·`JSON`으로 읽기 |
| `JSON`·`Dynamic`·`Variant`·`Time`에 `generateRandom` | 그럴듯한 JSON 스키마 생성 |

**실험 기능**

| | |
|---|---|
| 컬럼 캐시 | `use_columns_cache`: wide 파트의 역직렬화된 컬럼을 그래뉼 묶음 단위로 메모리에 보관. 비압축 캐시보다 저렴. *확인*: 설정 존재, 등급 Experimental |
| PromQL | 발표는 기본 100%, 확장 93% 호환을 인용합니다. 새 범위 함수(`stddev_over_time`, `mad_over_time` 등), `timestamp`, `step`, `range`, stale marker, 다수 수정. [TimeSeries + PromQL 랩](../../../usecase/timeseries-promql-oss/) 참고 |
| `PCO` 코덱 | `enable_pco_codec`, 고정 폭 숫자용 |
| Unity Catalog v2 | `DeltaLake`와 `Iceberg` 테이블을 카탈로그 하나로, `use_unity_catalog_v2` |
| 내장 Iceberg REST 카탈로그 | 네임스페이스는 메모리나 Keeper, 메타데이터는 S3 |
| `ipcrypt*` 함수 | 형식 보존 IP 암호화, 결정적 또는 프리픽스 보존 |
| Iceberg v3 deletion vector, `DROP PARTITION` | 읽기 지원, 단독 테이블과 REST 카탈로그에서 삭제 |
| 분산 플랜 | 단계 간 조인 런타임 필터, 교환 데이터 압축, 워커로 트레이스 전파 |

### 검증

다섯 `.sql` 파일의 모든 쿼리를 **26.10.3.7**
(`clickhouse/clickhouse-server:26.10`, 2026-10-28 pull)에서
`tools/hol run local/releases/26.10`으로 실행했고 — 다섯 개 PASS — 모든
`NN-*.sh`를 이 저장소의 seccomp 프로필로 띄운 `clickhouse-26-10` 컨테이너에서
끝까지 실행했습니다. 위의 수치·플랜 조각·에러 코드는 전부 그 실행 결과입니다.
26.9 비교는 이미 받아 두었던 `26.9` 이미지인 26.9.11.2에서 했습니다.

그다음 `00-setup.sh`를 독자처럼 실행해 `local/oss-docker`로 `clickhouse-26-10`을
띄우고, 다섯 개 `NN-*.sh`를 다시 실행해 같은 결과를 얻었습니다. 마지막 확인
단계는 서버가 떠 있어도 *Could not verify version*을 출력합니다. `/`의 응답에서
버전 문자열을 찾는데, 응답은 `Ok.`이기 때문입니다. 26.9 스크립트에도 같은
확인이 있습니다. 실제 확인은 `./01-lateral-join.sh`가 동작하는 것입니다.

작성 중 우회한 것이 셋 있고, 모두 SQL에 주석으로 남겼습니다.

- 에러는 `.sql` 파일을 그 줄에서 멈추므로, 거부 사례는 전부 `.sh` 러너에
  연결 하나씩 두었습니다 — 26.9 랩이 랩 04에서 쓴 것과 같은 분리입니다.
- 쿼리 조건 캐시 때문에 반복한 필터는 콜드 읽기보다 적은 행을 읽습니다. 처음
  LogsQL 측정은 캐시를 켠 채 해서 텍스트 인덱스를 쓰는 것처럼 보였습니다. 랩
  04는 `use_query_condition_cache = 0`으로 측정합니다.
- `query_log`는 모든 실행을 남기므로, 비교 쿼리는 `LIMIT 1 BY`로
  `log_comment`별 최신 행만 가져옵니다. 랩을 다시 돌려도 행이 쌓이지 않습니다.

changelog가 기대하게 만드는 것과 다른 관찰이 둘 있고 위에 표시했습니다. 블록
중첩 루프 조인이 새 `query_log` 조인 컬럼에서 빠지는 것(랩 01), 그리고 LogsQL
텍스트 필터가 텍스트 인덱스에 닿지 않는 것(랩 04)입니다.

---

**Happy Learning! 🚀**

## License

[MIT](../../../LICENSE) — same as the rest of the repository.

## 라이선스

[MIT](../../../LICENSE) — 저장소 전체와 동일합니다.
