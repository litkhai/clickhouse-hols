# Querying pg_lake's Iceberg tables from Postgres: pg_duckdb vs pg_clickhouse

*Ken, ClickHouse Solutions Architect · 2026-09-25 ·
[한국어](pg-lake-duckdb-vs-clickhouse.ko.md)*

> **Disclosure.** I work at ClickHouse. Everything below can be reproduced
> from the lab in this repository, and the places where pg_duckdb wins are
> reported as plainly as the places where it loses.

## TL;DR

- **pg_lake** lets Postgres move cold rows into Apache Iceberg tables
  registered in a REST catalog (Apache Polaris here). The question was which
  extension should serve analytics on that cold data: **pg_duckdb**, running
  DuckDB inside a separate Postgres, or **pg_clickhouse**, which pushes the
  query to ClickHouse reading the same Iceberg files.
- **Getting the three engines to read the same tables took two upstream
  fixes.** ClickHouse rejected pg_lake 3.5.3's manifests until pg_lake was
  patched ([pg_lake#659](https://github.com/Snowflake-Labs/pg_lake/issues/659)).
  The released pg_duckdb 1.1.1 silently returns **wrong answers** on
  month-partitioned tables
  ([duckdb-iceberg#699](https://github.com/duckdb/duckdb-iceberg/issues/699));
  only its main branch is correct.
- **Scans and aggregates are close.** pg_clickhouse wins where partition
  pruning or aggregation dominates (C1 in **30 ms** vs 166 ms). pg_duckdb wins
  small scans such as Q6 (**65 ms** vs 116 ms).
- **Joins favour pg_duckdb out of the box.** On Iceberg, ClickHouse
  needed one setting to pick a sane join order (Q3: 3.85 s → **0.61 s**). A
  semi-join that pg_clickhouse cannot push down made Q18 **20× slower** than
  pg_duckdb.
- **Load on the OLTP node** is where pg_clickhouse stands out. A fully pushed
  down query costs the main Postgres **0.01–0.03 core-seconds**. pg_duckdb
  keeps the main node free too, but needs a second Postgres holding a copy
  of the hot rows.

## The setup

A typical "ILM on Postgres" design keeps recent rows in heap tables and moves
older months to Iceberg. pg_lake does the moving and keeps the tables
registered in an Iceberg REST catalog. Anything that speaks Iceberg REST can
then read them.

```
 pg-main: PostgreSQL 18.6
 ├── hot rows (heap tables)
 ├── pg_lake 3.5.3 ─── writes ──►  Iceberg tables: Parquet + metadata in MinIO (S3),
 │                                 registered in Apache Polaris 1.7 (Iceberg REST)
 ├── A  pg_lake's own reader ─────────────────────── reads ──┤
 └── C  pg_clickhouse 0.10 ──► ClickHouse 26.9 ────── reads ──┤
                               (DataLakeCatalog)              │
 pg-duck: PostgreSQL 18 + pg_duckdb                           │
 └── B/B′  DuckDB iceberg extension (REST ATTACH) ── reads ──┘
```

| Path | What reads the Iceberg files | Where the CPU is spent |
|---|---|---|
| **A** pg_lake native | pg_lake's embedded DuckDB (`pgduck_server`) | the main Postgres node |
| **B** pg_duckdb 1.1.1 (release) | DuckDB `iceberg` extension, REST `ATTACH` | a separate Postgres node |
| **B′** pg_duckdb main (1.2.0-dev) | same, DuckDB 1.5.4 | a separate Postgres node |
| **C** pg_clickhouse 0.10.0 | ClickHouse `DataLakeCatalog` → Polaris | ClickHouse; Postgres only plans and fetches rows |

Nothing is loaded into ClickHouse tables: path C reads pg_lake's Iceberg files
in place. That was the point of the exercise.

**Data and rules.**
- The data is TPC-H SF10. `lineitem` (60 M rows) and `orders` are split at
  1998-02-01: newer rows stay in heap, and older months (53.9 M lineitem rows,
  73 monthly files, 1.8 GB) go to Iceberg partitioned by `month(date)`.
  Dimensions are Iceberg copies.
- Every engine container is capped at **4 vCPU / 4 GB** on one Docker VM (a
  12-vCPU Mac). Only the engines under test are running during a measurement.
- Each number is the **median of 5 warm runs** after an untimed warm-up.
  Every result is checked against path A with an order-independent hash.

The nine queries cover five tiers: scan/aggregate (Q1, Q6, C1), high
cardinality (C2), joins (Q3, Q5), complex (Q18) and ILM (C5 spans hot and
cold, C6 is a point lookup).

## Wiring it up

**pg_duckdb** attaches the Polaris catalog per session, so the lab uses a
PG18 login event trigger. It cannot use an `EXCEPTION` block, because DuckDB
rejects the subtransaction:

```sql
CREATE FUNCTION bench_attach_polaris() RETURNS event_trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM duckdb.raw_query($q$CREATE SECRET IF NOT EXISTS polaris_s (TYPE iceberg,
      CLIENT_ID '…', CLIENT_SECRET '…',
      OAUTH2_SERVER_URI 'http://polaris:8181/api/catalog/v1/oauth/tokens')$q$);
  PERFORM duckdb.raw_query($q$ATTACH IF NOT EXISTS 'ilm' AS polaris (TYPE iceberg,
      SECRET polaris_s, ENDPOINT 'http://polaris:8181/api/catalog',
      ACCESS_DELEGATION_MODE 'none')$q$);
END $$;
CREATE EVENT TRIGGER bench_attach_polaris ON login EXECUTE FUNCTION bench_attach_polaris();
```

**pg_clickhouse** needs a ClickHouse database over the catalog, then a
standard foreign server. With MinIO and no STS, `vended_credentials = false`
is required, or Polaris refuses the table load:

```sql
-- ClickHouse
CREATE DATABASE polaris ENGINE = DataLakeCatalog('http://polaris:8181/api/catalog', '<s3 key>', '<s3 secret>')
SETTINGS catalog_type = 'rest', warehouse = 'ilm', catalog_credential = '<id>:<secret>',
         oauth_server_uri = 'http://polaris:8181/api/catalog/v1/oauth/tokens',
         storage_endpoint = 'http://minio:9000/warehouse', vended_credentials = false;
CREATE VIEW bench.lineitem_cold AS SELECT * FROM polaris.`tpch.lineitem_cold`;

-- Postgres
CREATE SERVER ch FOREIGN DATA WRAPPER clickhouse_fdw
  OPTIONS (driver 'binary', host 'clickhouse', port '9000', dbname 'bench');
IMPORT FOREIGN SCHEMA bench FROM SERVER ch INTO ch;
```

The views exist because catalog tables are named `tpch.lineitem_cold`, which
an FDW cannot import as-is.

## Surprise 1: ClickHouse could not read pg_lake's tables

The first query from ClickHouse failed with `No partition-spec in iceberg
manifest file`. The Iceberg spec requires every manifest file to carry
key-value metadata (`schema`, `schema-id`, `partition-spec`,
`partition-spec-id`, `format-version`, `content`). pg_lake 3.5.3 writes only
the Avro defaults. Lenient readers, including pg_lake's own DuckDB, ignore
this; a spec-strict reader does not.

This is a writer bug, not a pg_clickhouse one. It is reported as
[pg_lake#659](https://github.com/Snowflake-Labs/pg_lake/issues/659), with a
patch on a fork. The lab builds pg_lake with that patch, so **every path-C
number in this post is "pg_lake + patch"**. Without it, ClickHouse cannot read
the tables at all.

## Surprise 2: the released pg_duckdb returns wrong answers

pg_duckdb 1.1.1 (DuckDB 1.4.3) produced a Q6 revenue that did not match the
other engines. The monthly count C1 returned **0 rows instead of 3**. There was
no error.

The iceberg extension in that build computes the `month()` partition
transform as `days / 30`. With range filters it therefore prunes files it
must read: a filter from 1994-01-01 drops January–April 1994. This is
[duckdb-iceberg#699](https://github.com/duckdb/duckdb-iceberg/issues/699),
fixed upstream. pg_duckdb main (1.2.0-dev, DuckDB 1.5.4) has the fix, but no
release does yet, so we asked for one in
[pg_duckdb#1083](https://github.com/duckdb/pg_duckdb/issues/1083).

**The pg_duckdb numbers below are from the main build (B′).** B 1.1.1 was only
run to confirm the wrong answers.

## Results

![Warm latency per query](../results/charts/query_latency_sf10.png)

| Tier | Query | A pg_lake | B′ pg_duckdb | C pg_clickhouse | C + join swap |
|---|---|---:|---:|---:|---:|
| L1 | Q6 revenue forecast | 233 ms | **65 ms** | 116 ms | 153 ms |
| L1 | C1 monthly count, one quarter | 327 ms | 166 ms | **30 ms** | 31 ms |
| L1 | Q1 pricing summary | 921 ms | **625 ms** | 797 ms | 905 ms |
| L2 | C2 top 100 customers | 524 ms | 270 ms | **175 ms** | 252 ms |
| L3 | Q3 shipping priority | 799 ms | **278 ms** | 3.85 s | 608 ms |
| L3 | Q5 local supplier volume | 934 ms | **487 ms** | 863 ms | 811 ms |
| L4 | Q18 large volume customer | 2.09 s | **1.09 s** | 22.2 s | 20.2 s |
| L5 | C5 last 12 months (hot + cold) | 844 ms | **200 ms** | 636 ms | 628 ms |
| L5 | C6 point lookup (hot + cold) | 347 ms | 82 ms | 77 ms | **61 ms** |

A note on precision: queries that the join-swap setting cannot affect (Q6, C2)
moved by up to 30 % between the two C runs. Treat differences smaller than
that as ties.

**Scans and aggregates (L1–L2).**
- pg_clickhouse wins where it can prune or aggregate aggressively. C1 counts
  rows per month in one quarter; ClickHouse opens only three monthly files and
  answers in 30 ms.
- pg_duckdb wins the small, selective scan Q6.
- On a full scan (Q1) all three are within 1.5× of each other.

**Joins (L3–L4).** pg_duckdb is faster by default, and two causes explain
nearly all of the gap.

### Q3: join order on Iceberg

Q3's pushed-down SQL takes 3.5–3.7 s even when run directly in ClickHouse, so
pg_clickhouse is not adding the time. ClickHouse's hash join builds its hash
table from the **right** side. The generated SQL lists
`customer ⋈ orders ⋈ lineitem`, which makes the 54 M-row `lineitem` the
build side.

`query_plan_join_swap_table` defaults to `auto`, which should correct this.
It did not here. Our reading is that it has no row estimates for tables
behind `DataLakeCatalog`. Forcing the swap from Postgres fixes it:

```sql
SET pg_clickhouse.session_settings =
  'join_use_nulls 1, group_by_use_nulls 1, final 1, transform_null_in 0, query_plan_join_swap_table 1';
```

Keep pg_clickhouse's defaults in the string: pushdown correctness depends on
`join_use_nulls` and `transform_null_in`. With the swap, Q3 drops from 3.85 s
to **0.61 s** and Q5 improves slightly. pg_duckdb is still ahead on Q3
(278 ms), but the gap shrinks from 14× to about 2×.

### Q18: a semi-join that stays in Postgres

Q18 filters orders with `o_orderkey IN (SELECT l_orderkey … GROUP BY
l_orderkey HAVING sum(l_quantity) > 300)`. pg_clickhouse 0.10.0 pushes the
three-table join and the subquery as **two separate** remote queries. The join
result, every cold lineitem row with its customer and order, streams back to
Postgres, and Postgres does the semi-join. That takes 22 s, and 14
core-seconds on the main node. Rewriting the `IN` as an explicit join to the
aggregated subquery yields the same plan.

ClickHouse itself runs Q18 in about 4 s. To get that from Postgres, the whole
query has to go down as one. A view in ClickHouse holding the `IN` does it:

```sql
-- ClickHouse
CREATE VIEW bench.orders_big AS
SELECT * FROM bench.orders_cold
WHERE o_orderkey IN (SELECT l_orderkey FROM bench.lineitem_cold
                     GROUP BY l_orderkey HAVING sum(l_quantity) > 300);
-- Postgres: IMPORT FOREIGN SCHEMA bench LIMIT TO (orders_big) FROM SERVER ch INTO ch;
-- then join customer, ch.orders_big and lineitem as usual.
```

The query is then pushed down whole, with identical results. It took
8.2–8.9 s, and **4.2 s** with the join swap. These were timed by hand in psql
(3 runs), not by the harness. That is still slower than pg_duckdb's 1.09 s,
but it is no longer 20×.

**ILM views (L5).** C5 and C6 combine heap and Iceberg in a `UNION ALL` view,
so Postgres always does part of the work.
- pg_duckdb reads its local copy of the hot rows and wins C5.
- The point lookup C6 is a tie at 60–80 ms.

## The cost on the OLTP node

For many teams latency is secondary. What matters is that analytics does not
slow down the primary. The lab measures cgroup CPU per container.

| Query | A: main node | C: main node | C: ClickHouse | B′: second node |
|---|---:|---:|---:|---:|
| Q1 | 2.81 | 0.01 | 3.10 | 2.34 |
| Q6 | 0.34 | 0.01 | 0.29 | 0.13 |
| Q3 | 1.47 | 0.03 | 6.86 | 0.77 |
| Q5 | 2.07 | 0.01 | 2.86 | 1.37 |
| Q18 | 5.23 | **14.04** | 26.12 | 4.03 |
| C5 | 1.33 | 0.62 | 0.10 | 0.73 |

(median core-seconds per query)

- **pg_lake's own reader (A)** puts all of it on the primary.
- **pg_clickhouse (C)** puts almost none on it when the query is pushed down.
  When it is not (Q18), it is worse than doing nothing at all.
- **pg_duckdb (B′)** also keeps the primary idle, but it needs a replica or
  a separate Postgres. The hot rows must be copied there for ILM views; the
  lab uses `pg_dump`.

## Which one?

- **pg_duckdb (main build) for join-heavy ad-hoc SQL.** It is the fastest path
  for most joins, and the whole plan runs in one engine with no pushdown
  boundary. Pin a build that includes the duckdb-iceberg month-transform fix,
  and give it its own Postgres.
- **pg_clickhouse to keep the primary Postgres untouched** and to add
  analytics capacity without another Postgres. It is at its best on
  aggregations and pruning-friendly filters.
  - Set `query_plan_join_swap_table 1` for Iceberg-backed joins.
  - Check `EXPLAIN (VERBOSE)` for anything that is not in `Remote SQL`.
  - Semi-joins against aggregated subqueries belong in a ClickHouse view.
- **Either way, test the Iceberg writer against the reader.** Two of the three
  readers here disagreed with the writer before any tuning started.

## Caveats

- This is one SF10 dataset on one laptop VM. Run-to-run noise was up to 30 %.
- Only warm runs were measured. There were no cold-cache runs and no
  concurrency test.
- Dimensions lived in Iceberg (D1). The mixed case, with dimensions in heap,
  was not measured.
- Path C runs on a patched pg_lake until pg_lake#659 lands.
- The Q18 view workaround and the direct-ClickHouse timings were measured by
  hand, not by the harness.

## Reproduce

Everything is in `local/pg-analytics` of the
[clickhouse-hols](https://github.com/litkhai/clickhouse-hols) repository. It
has Docker Compose for Polaris, MinIO, two Postgres flavours and ClickHouse,
plus scripts that build, load, verify and benchmark.

```bash
cd local/pg-analytics
./00-setup.sh      # builds PG 18 + pg_lake (+ patch) + pg_clickhouse, starts the stack
./run-all.sh 10    # SF10 bulk load, integration gate, all paths, ~25 min
./07-report.sh     # tables and charts
```

Full numbers, including min–max per query, are in
[RESULTS.md](../RESULTS.md). The test design is in
[docs/DESIGN.md](../docs/DESIGN.md).
