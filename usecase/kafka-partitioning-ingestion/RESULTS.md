# Verified raw results — kafka-partitioning-ingestion

Captured end-to-end on **ClickHouse 26.6.1** + **Apache Kafka 3.9.0 (KRaft)** +
**Kafka Connect 7.8.0 / clickhouse-kafka-connect v1.3.9**, all single-node Docker.

- **10,000,000 events per topic**, 10,000 customers (`customer_id ∈ [0,9999]`)
- **8 partitions** per topic; point-lookup key = **`customer_id = 4242`**
- Background **merges stopped** on every target (so the streaming steady-state,
  many unmerged parts, stays observable) — except the explicit merge demo in §C.
- The **only** difference between `events_aligned` and `events_misaligned` is the
  **partitioner** (range = `customer_id // 1250` vs hash = murmur2 of the key).
  Identical data, identical interleaved time order.

The 5 targets:

| target | path | engine config | source topic |
|---|---|---|---|
| `engine_misaligned` | B Kafka engine, tuned | `num_consumers=8, thread_per_consumer=1` | hash |
| `engine_aligned` | B Kafka engine, tuned | `num_consumers=8, thread_per_consumer=1` | range |
| `engine_default_aligned` | A Kafka engine, **default** | single consumer | range |
| `connect_misaligned` | C Connect Sink | per-partition batching | hash |
| `connect_aligned` | C Connect Sink | per-partition batching | range |

---

## §6.1 — rows & parts per target

```
table                    parts      rows
connect_aligned          1861   10000000
connect_misaligned       1836   10000000
engine_aligned             38   10000000
engine_default_aligned     10   10000000
engine_misaligned          32   10000000
```

## §6.2 — per-part `customer_id` span (the WHY).  Lower avg = better part pruning.

```
table                    parts  avg_span  max_span
engine_misaligned           32      9992      9995   ← every part = full range
engine_aligned              38      1249      1249   ← each part = one partition bucket (10000/8)
engine_default_aligned      10      9999      9999   ← DILUTED: single consumer multiplexed partitions
connect_misaligned        1836      9989      9995   ← every part = full range
connect_aligned           1861      1249      1249   ← per-partition batching kept locality
```

## §6.3 — `EXPLAIN ESTIMATE` for `WHERE customer_id = 4242`  (parts · rows · marks to read)

```
table                    parts      rows   marks
engine_misaligned           32    262144      32
engine_aligned               5     40960       5     ← only the 5 parts of bucket 3 overlap
engine_default_aligned      10     82418      10     ← diluted: must read all parts
connect_misaligned        1836   7839808    1836     ← worst: 1836 full-range tiny parts
connect_aligned            234    996619     234     ← narrow, but 234 tiny parts overlap → see §C
```

## §6.4 — actual measured cost (`system.query_log`)

```
probe                       read_rows   read_bytes   duration_ms
engine_misaligned              262144     1.13 MiB            21
engine_aligned                  40960   320.00 KiB             5
engine_default_aligned          82418   603.51 KiB             9
connect_misaligned            7839808    33.44 MiB           685
connect_aligned                996619     7.38 MiB           134
```

---

## §A — per-part `customer_id` min/max (proof the ranges are disjoint vs overlapping)

`engine_aligned` — each part covers exactly one partition's contiguous bucket
(multiple parts per bucket because each consumer flushed several times in 60 s):

```
_part           rows    lo    hi
all_11_11_0   325355     0  1249
all_4_4_0     180135     0  1249
all_27_27_0   321916     0  1249
all_35_35_0   102190     0  1249
all_19_19_0   321583     0  1249
all_37_37_0    97817  1250  2499
all_29_29_0   322313  1250  2499
all_21_21_0   322764  1250  2499
all_13_13_0   323466  1250  2499
all_6_6_0     184092  1250  2499
all_18_18_0   323124  2500  3749
all_26_26_0   320705  2500  3749
```

`engine_misaligned` — every part spans the whole key space, so none can be skipped:

```
_part           rows   lo    hi
all_10_10_0   323423    4  9991
all_11_11_0   323679    1  9994
all_12_12_0   325062    5  9990
all_13_13_0   339960    3  9996
all_14_14_0   339035    7  9999
all_15_15_0   335949    6  9998
```

## §B — `EXPLAIN indexes = 1` (granule-level proof)

```
engine_aligned     →  Parts: 5/38     Granules: 5/1216
engine_misaligned  →  Parts: 32/32    Granules: 32/1220
```

## §C — Connect's part-explosion is mitigated by merges (and merges keep locality)

```
connect_aligned BEFORE merge:  1861 parts → EXPLAIN ESTIMATE reads 234 parts / 996619 rows
  (SYSTEM START MERGES + OPTIMIZE TABLE connect_aligned FINAL)
connect_aligned AFTER  merge:     1 part  → EXPLAIN ESTIMATE reads   1 part /   8192 rows
```

Takeaway: Connect Sink keeps per-part locality with no ClickHouse tuning, but its
small per-poll batches create many tiny parts. You rely on background merges to
consolidate them; because merges preserve `ORDER BY`, locality survives the merge.

## §D — deterministic SQL proof (`00-explain-estimate.sql`, no Kafka)

```
sql_misaligned  →  EXPLAIN ESTIMATE: parts=20  rows=163840  marks=20
sql_aligned     →  EXPLAIN ESTIMATE: parts=1   rows=8192    marks=1
```

## §E — wall-clock point lookup (`07-benchmark.sh`, ms; fixed overhead dominates at this scale)

```
engine_misaligned        ~0.002 s
engine_aligned           ~0.002 s
engine_default_aligned   ~0.002 s
connect_misaligned       ~0.029–0.064 s   (1836 parts to open)
connect_aligned          ~0.002 s         (after the §C merge → 1 part)
```

`read_rows` / `marks` are the deterministic proof; latency widens as data volume
and unmerged part counts grow.
