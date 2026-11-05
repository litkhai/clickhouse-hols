# Upsert, UPDATE and DELETE across ClickHouse versions

[English](#english) | [한국어](#한국어)

---

## English

The same SQL for every way of changing rows in ClickHouse, run on six builds (the LTS lines 24.8, 25.3,
25.8, 26.3, 26.8 and the latest stable 26.10). For each way the runner records: does it run on that
version (or which error code), how long it takes, what it writes (bytes, from `system.part_log`), how
soon the change is visible, and what it costs later `SELECT`s. Nothing here is quoted from a changelog:
every cell in [RESULTS.md](RESULTS.md) comes from a run, and the raw per-probe data (including
`query_log` rows) is in `results/<version>.json`.

The ways: `ReplacingMergeTree` (with and without `is_deleted`), `CollapsingMergeTree` and
`VersionedCollapsingMergeTree`, `CoalescingMergeTree`, classic `ALTER TABLE ... UPDATE`, the SQL
`UPDATE` (patch parts), re-inserting with a higher version, on-the-fly mutations, and three kinds of
`DELETE`.

### Run it

```bash
cd workload/upsert-across-versions
./run_matrix.py                      # all six versions, about 17 minutes; pulls nothing, images must exist
./run_matrix.py --versions 26.10     # one version (prefix of a line in versions.txt)
./run_matrix.py --only 04            # one file or probe-id prefix; results merge into the JSON
./run_matrix.py --report-only        # rebuild RESULTS.md from results/*.json
tools/hol run workload/upsert-across-versions   # from the repository root: the SQL on 26.10 only, must not raise
```

`versions.txt` pins the exact tags, oldest first. `run_matrix.py` is the runner of
[workload/join-across-versions](../join-across-versions/) (same file; containers are named `uav-<tag>`
here and `jav-<tag>` there). A statement preceded by `-- probe: <id> [repeat=N] [value]` is a probe, the
others are setup; `value` puts the first result row in the table cell. `-- settings: a, b` lists
settings to look up in `system.settings`, then in `system.merge_tree_settings` (shown as `[table]`).
Each statement runs in its own `clickhouse-client` call, so there is no bare `SET`.

### Probes

| File | What it does |
|---|---|
| `01-replacing.sql` | `ReplacingMergeTree(ver)` and `(ver, is_deleted)`, 2M keys, then 1% re-written with a higher `ver`, 0.1% marked deleted: `count()` without and with `FINAL`, `FINAL` vs `argMax ... GROUP BY` (5 repeats), `OPTIMIZE ... FINAL`, `FINAL CLEANUP` |
| `02-collapsing.sql` | `CollapsingMergeTree` and `VersionedCollapsingMergeTree` with the cancel row inserted before the state row; a state-first control |
| `03-coalescing.sql` | `CoalescingMergeTree` with sparse inserts vs the same inserts into `ReplacingMergeTree` |
| `04-update-mechanisms.sql` | classic `ALTER UPDATE`, re-insert into `ReplacingMergeTree` and patch-part `UPDATE`, each at 1 row, 1% and 10% of 2M rows (one table each): duration, bytes written, patch parts, then a full-scan `SELECT sum(v)` (5 repeats) against untouched control tables |
| `05-on-the-fly.sql` | a pending mutation (`SYSTEM STOP MERGES`, `mutations_sync = 0`) read with `apply_mutations_on_fly` 1 and 0 |
| `06-patch-accumulation.sql` | 50 successive one-row `UPDATE`s: patch-part count, scan and point read after 1, 10, 50; then `OPTIMIZE ... FINAL` and `ALTER TABLE ... APPLY PATCHES` |
| `07-delete.sql` | `ALTER ... DELETE`, `DELETE FROM`, `DELETE FROM` with `lightweight_delete_mode = 'lightweight_update'`: duration, bytes, `count()` with `apply_deleted_mask` 1 and 0 |
| `08-scale.sql` | the read-side cost of file 04 at 20M rows (a scan of 130 to 480 ms): classic `ALTER UPDATE`, patch-part `UPDATE` and re-insert at 1% and 10%, a full-scan aggregate and a 100,000-row range read (5 repeats each) against untouched controls |
| `errors/01-expected-failures.sql` | statements that fail even on 26.10 (UPDATE without block columns, forced lightweight DELETE, `CLEANUP` without its table setting, UPDATE of a sort-key column). `tools/hol` does not run this directory; the runner does |

Every probe in the top-level files succeeds on 26.10 (`tools/hol run` stops at the first exception).
Failures on older versions are the result, shown as `✗ Code N` (56 UNKNOWN_STORAGE, 62 SYNTAX_ERROR,
115 UNKNOWN_SETTING, 344 SUPPORT_IS_DISABLED, 420 CANNOT_UPDATE_COLUMN, 48 NOT_IMPLEMENTED).

### What changed between versions

Written only from [RESULTS.md](RESULTS.md) (run on 2026-11-04, 12 CPUs, 15.6 GiB Docker VM). Other
containers were running during the whole run (RESULTS.md lists their CPU% per version; the 26.10 run
overlapped with about 300% of other load), and most timed probes take 4 to 30 ms, so differences of a
few milliseconds are not used below.

- **Patch-part `UPDATE`.** Syntax error (Code 62) on 24.8.14.39 and 25.3.14.14; it runs from 25.8.33.6.
  It needs a table created with `enable_block_number_column = 1` and `enable_block_offset_column = 1`
  (without them: Code 48, "Lightweight updates are supported only for tables with materialized
  _block_number column", same on 25.8 to 26.10; `err-update-no-block-columns`). It needs no session
  setting: `04-pu-no-setting` (no `SETTINGS` clause) runs on 25.8 to 26.10. The setting
  `allow_experimental_lightweight_update` exists from 25.8 as `Beta` and as `Production` on 26.10.
  `UPDATE` of a sort-key column fails with Code 420 (patch part and classic mutation alike).
- **How a patch part looks.** In `system.parts`, a patch part has a name starting with `patch-`, for
  example `patch-<hash>-all_4_4_0_3`, and `part_type` Compact. In `system.part_log` it is a `NewPart`.
  There is no patch column in `system.parts`; the probes find them with `startsWith(name, 'patch-')`.
- **Lightweight `DELETE`.** `DELETE FROM` runs on all six versions. `lightweight_delete_mode` exists
  from 25.8 (default `alter_update`; on 24.8 and 25.3 setting it is Code 115). In the default mode
  `DELETE FROM` is a `MutatePart` that writes about 11 KB (24.8) to 18 KB (26.10) for 1% of 2M rows;
  `ALTER ... DELETE` writes 16 MB. With `lightweight_delete_mode = 'lightweight_update'` on a table with
  the block columns the server writes a patch part instead (`07-delete-patch-bytes`: 5 KB on 25.8 and 26.3,
  92 KB on 26.8 and 26.10, no `MutatePart`; the jump has the same cause as the patch bytes, item 2 of
  *Explained after the run* below). `lightweight_update_force` on a table without the block columns
  fails with Code 344 (`err-delete-force-no-block-columns`). With `apply_deleted_mask = 0` the deleted rows
  are back (`count()` 2,000,000 against 1,980,000) on every version, and for the patch mode from 25.8.
- **Patch bytes.** For the same 1% update the patch part is 93 KB (10%: 845 KB) on 25.8.33.6 and
  26.3.62.3; on 26.8.36.3 and 26.10.3.7 they are 180 KB
  and 1.65 MB. From 26.8 a patch part also stores the table's sort key (item 2 below).
- **On-the-fly mutations.** `apply_mutations_on_fly = 1` returns the new value on 25.3.14.14 and
  later; on 24.8.14.39 the setting exists but the read still returns the old value
  (`05-read-on-fly`).
- **`APPLY PATCHES`.** `ALTER TABLE ... APPLY PATCHES` ran on 25.8 to 26.10. After 50 patches,
  `OPTIMIZE ... FINAL` renamed the base part (`all_1_2_1` to `all_1_2_2_101`) and left one active
  patch part holding the 50 rows; `APPLY PATCHES` renamed it again (`..._103`). The probe right after it
  found no active patch part on 25.8.33.6 and the 50-row patch part still active on 26.3.62.3, 26.8.36.3
  and 26.10.3.7. It is removed in the background on every build, about 1 s later on 25.8 and 28 to 36 s
  later on 26.3 to 26.10 (item 1 below). Scan and point-read results are identical in all steps.
- **`ReplacingMergeTree`.** Same results on all six versions: 2,020,000 rows without `FINAL`,
  2,000,000 with it; a plain `OPTIMIZE FINAL` on the `is_deleted` table leaves the 2,000 deleted rows
  (2,000,000 physical rows); `OPTIMIZE ... FINAL CLEANUP` removes them (1,998,000) but only when the
  table was created with `allow_experimental_replacing_merge_with_cleanup = 1`; without it, Code 344
  on every version.
- **`CollapsingMergeTree`, cancel row first.** Same on all six versions. After `OPTIMIZE ... FINAL`
  the table keeps 101,000 rows: for each of the 1,000 cancelled keys both the -1 and the +1 row stay
  (`sum(sign)` is 99,000 and the -1 count is 1,000). `FINAL` before the merge returns 100,000 rows.
  `HAVING sum(sign) > 0` returns the 99,000 correct keys. The state-first control and
  `VersionedCollapsingMergeTree` with the cancel row first both end with 99,000 rows.
- **`CoalescingMergeTree`.** Code 56 (unknown engine) on 24.8.14.39 and 25.3.14.14; from 25.8.33.6 the
  three sparse inserts become one row per key with all three columns set under `FINAL` and after
  `OPTIMIZE`, where `ReplacingMergeTree` keeps only the last insert's column.

### 1 row / 1% / 10% on 2M rows

Bytes written come from `system.part_log` (`ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']`),
the update times are single runs, and the `SELECT sum(v)` columns are median (fastest) of 5 repeats in
ms. Controls: untouched `MergeTree` 4 (4) ms on 26.10 and 9 (5) on 24.8; untouched `ReplacingMergeTree`
with `FINAL` 5 (4) on 26.10. Values are 26.10.3.7; the oldest build where the mechanism runs is in
brackets (24.8.14.39 for classic and re-insert, 25.8.33.6 for patch parts).

| Mechanism | Fraction | Bytes written | Update time | `SELECT sum(v)` |
|---|---|---|---|---|
| classic `ALTER UPDATE` | 1 row | 8.0 MB [8.0 MB] | 90 ms [101] | 5 (4) [6 (5)] |
| | 1% | 7.9 MB [7.9 MB] | 98 ms [69] | 6 (5) [6 (5)] |
| | 10% | 7.2 MB [7.2 MB] | 75 ms [78] | 6 (4) [5 (5)] |
| re-insert, `ReplacingMergeTree` | 1 row | 1.8 KB [0.9 KB] | 64 ms [2] | `FINAL` 6 (5) [18 (17)] |
| | 1% | 186 KB [179 KB] | 65 ms [11] | `FINAL` 14 (13) [23 (18)] |
| | 10% | 1.65 MB [1.64 MB] | 26 ms [85] | `FINAL` 16 (15) [34 (16)] |
| patch-part `UPDATE` | 1 row | 2.0 KB [2.2 KB] | 4 ms [6] | 14 (10) [7 (6)] |
| | 1% | 180 KB [93 KB] | 21 ms [20] | 12 (11) [8 (7)] |
| | 10% | 1.65 MB [845 KB] | 28 ms [44] | 17 (11) [12 (10)] |

Reading the table: the classic mutation rewrites the whole `v` column (about 8 MB) at every fraction, the
re-insert and the patch part write roughly in proportion to the changed rows. After the change, a scan
of a mutated table costs the same as the control within the 1 ms resolution; the re-insert needs
`FINAL` (14 to 16 ms on 26.10 against 5 ms for an untouched `ReplacingMergeTree` with `FINAL`; without
`FINAL` it is fast and wrong, the sum counts the re-written keys twice); the patch-part table reads
12 to 17 ms against 4 ms for the control while the patch is still a separate part. The update times of
the re-insert on 26.10 and 24.8 differ by more than their difference in work, so they are noise; do not
rank mechanisms by them. Only a 2M-row table and one data layout (the changed rows spread over every
granule at 1% and 10%) were measured; the 10% threshold the lab was started from is not tested by
anything beyond these three fractions.

### Read cost at 20M rows (`08-scale.sql`)

The same three mechanisms at 10x the size, so a scan takes 130 to 480 ms and the 1 ms resolution no
longer matters. Each table is one part before the change, the patch-part and re-insert tables have
merges stopped, and the re-insert tables are read with `FINAL`. The scan is
`SELECT sum(sipHash64(v, s)), uniq(v)` over every row; the range read is the same aggregate over 100,000
ids on the sort key. Cells are median (fastest) of 5 repeats in ms, 26.10.3.7 first and the oldest build
where the mechanism runs in brackets (24.8.14.39; 25.8.33.6 for patch parts). The run took 74 to 121 s
per version; other containers were running (RESULTS.md has their CPU%, total 88% to 459% of 1200%), so
read differences smaller than about 30% as noise. On 26.10.3.7 `OPTIMIZE ... FINAL` writes every 20M-row
table with `ZSTD(3)`, on the other builds with `LZ4` (item 3 below); the patch parts and the re-inserted
parts are `LZ4` on every build. So a bracketed value differs from the 26.10 one in codec as well as in build.

| Read | Fraction | untouched control | classic `ALTER UPDATE` | patch-part `UPDATE` | re-insert, `FINAL` |
|---|---|---|---|---|---|
| full scan | 1% | 148 (134) [193 (172)] | 149 (124) [218 (189)] | 202 (185) [186 (173)] | 274 (248) [278 (224)] |
| full scan | 10% | 148 (134) [193 (172)] | 161 (128) [159 (150)] | 242 (204) [270 (229)] | 255 (223) [376 (290)] |
| range, 100k rows | 1% | 5 (3) [5 (5)] | 3 (3) [12 (7)] | 5 (4) [6 (5)] | 7 (5) [10 (8)] |
| range, 100k rows | 10% | 5 (3) [5 (5)] | 4 (3) [14 (11)] | 5 (5) [8 (7)] | 6 (5) [17 (12)] |

The control for the re-insert column is an untouched `ReplacingMergeTree` read with `FINAL`: 154 (131)
on 26.10.3.7 and 170 (149) on 24.8.14.39 for the full scan, 3 (3) and 8 (4) for the range. The untouched
`MergeTree` is the control for the other columns. Without `FINAL`, the re-insert table scans in 157 (148) ms
on 26.10 but returns a wrong sum.

What the 26.10 numbers show: a classic-mutated table scans like the control; the patch-part table
scans about 1.4x to 1.6x the control, and the `FINAL` table about 1.7x to 1.8x (against the untouched
`FINAL` table, 154 (131), about 1.7x). Range reads on the sort key stay in single-digit
milliseconds for every mechanism. The updates themselves (single runs, 26.10.3.7): classic 1.37 s (1%)
and 0.80 s (10%), writing 20 MB for both; patch part 125 ms and 269 ms, writing 1.8 MB and 16 MB;
re-insert 63 ms and 255 ms, writing 1.8 MB and 9.2 MB.

What changes between builds, from the same file:

- **Patch part, bytes written.** 916 KB (1%) and 8.4 MB (10%) on 25.8.33.6 and 26.3.62.3; 1.79 MB and
  16.4 MB on 26.8.36.3 and 26.10.3.7, for the same changed rows (200,000 and 2,000,000); item 2 below.
- **Patch part, update time (1% / 10%).** 137 / 734 ms on 25.8, 141 / 553 ms on 26.3, 100 / 832 ms on
  26.8, 125 / 269 ms on 26.10 (single runs).
- **Patch part, scan (1% / 10%).** 186 (173) / 270 (229) on 25.8 against a control of 252 (203); 367 (226)
  / 229 (160) on 26.3 against 147 (120); 281 (200) / 242 (213) on 26.8 against 209 (166); 202 (185) / 242
  (204) on 26.10 against 148 (134). The control itself varies by 1.7x between builds on this loaded
  machine, so the overhead ratios of 25.8 to 26.8 are not reliable; these runs do not separate the builds.
- **Classic mutation, bytes written.** 79 MB (1%) and 72 MB (10%) on 24.8 to 26.8; 20.5 MB and 19.6 MB on
  26.10.3.7. At 2M rows (file 04) all six builds wrote 7 to 8 MB. The mutation is the same; 26.10
  compresses the 20M-row part with `ZSTD(3)` (item 3 below).
- **Not available.** Patch parts are Code 62 on 24.8 and 25.3, as in file 04; their classic and
  re-insert tables ran.

### Explained after the run (2026-11-05)

Three of the differences above were first recorded without a cause. On 2026-11-05 each one was reproduced
with a control on throwaway containers of 25.8.33.6, 26.3.62.3, 26.8.36.3 and 26.10.3.7 (other containers
used about 230% of 1200% CPU at the start and 43% at the end; only bytes, part names and log lines are
used, no timings). The cause was read in the ClickHouse source: `v25.8.33.6-lts`, and for the other builds
the nearest public tags `v26.3.60.2-lts`, `v26.8.34.13-lts` and `v26.10.2.103-stable`, because the
26.3.62.3, 26.8.36.3 and 26.10.3.7 build commits (`system.build_options`) are not on GitHub. None of the
three is a bug. The reproductions are in [`explain/`](explain/); run one with
`clickhouse-client --multiquery < explain/<file>` (the runner and `tools/hol` do not run this directory).

1. **The patch part left after `APPLY PATCHES` is removed later by the cleanup.** On every build the server
   log has `Will drop unused patch part ...` for it: 1.0 s after `APPLY PATCHES` finished on 25.8.33.6,
   28.6 s on 26.3.62.3, 27.9 s on 26.8.36.3 and 36.3 s on 26.10.3.7. On 25.8, `clearUnusedPatchParts` ran
   from the table's merge and mutation scheduler (`StorageMergeTree::scheduleDataProcessingJob`) at most
   every `merge_tree_clear_old_parts_interval_seconds` (1 s). From 26.3 it
   runs in a separate cleanup thread
   ([ClickHouse#91574](https://github.com/ClickHouse/ClickHouse/pull/91574), merged into 26.3.1.471,
   `MergeTreeCleanupThread`). That thread sleeps between `cleanup_delay_period` (30 s) and `max_cleanup_delay_period` (300 s), longer after
   a pass that removed little, plus up to `cleanup_delay_period_random_add` (10 s). The setting's
   description agrees: `remove_unused_patch_parts` removes such parts "in background".
   `explain/01-patch-cleanup.sql` reads `system.parts` 3 s after `APPLY PATCHES`. With default settings the
   patch part is gone on 25.8 and still there on 26.3 to 26.10. When the three cleanup settings are 1, 1
   and 0 it is gone on all four builds. With the same cadence and `remove_unused_patch_parts = 0` it stays
   on all four. Setting only `cleanup_delay_period = 1` is not enough: after a pass that removed almost
   nothing, the 26.10 trace said `Scheduling next cleanup after 75000ms`.
2. **From 26.8 a patch part stores the table's sort key.** 26.8 adds the table setting
   `patch_parts_version`, default `v2`
   ([ClickHouse#103182](https://github.com/ClickHouse/ClickHouse/pull/103182) "Lightweight Updates v2", a
   backward-incompatible change, re-landed as [ClickHouse#116007](https://github.com/ClickHouse/ClickHouse/pull/116007) and backported to 26.8 as
   [ClickHouse#116373](https://github.com/ClickHouse/ClickHouse/pull/116373);
   `v26.8.1.2041-lts` already defaults to `v2`). A `v1` patch part holds `v`, `_part`, `_part_offset`,
   `_part_data_version`, `_block_number` and `_block_offset`, sorted by `(_part, _part_offset)`. A `v2` patch
   part holds the sort-key columns (here `id`) in place of `_part_offset` and is sorted by
   `(id, _block_number, _block_offset)`. According to the setting's description, applying a `v2` patch needs
   memory for the largest run of equal keys instead of the whole patch. Both are 820,086 bytes
   uncompressed for 1% of 2M rows. The difference is the codec: `_part_offset` gets the `Delta, LZ4` codec of
   `_block_offset` (`addCodecsForPatchSystemColumns` in `PatchParts/PatchPartsUtils.cpp`; about 300 bytes per
   compressed block in `clickhouse-compressor --stat`), and `id` gets the table's codec, `LZ4` (36 to 52 KB
   per block, as much as `v`). That makes 91,118 against 178,248 compressed bytes.
   `explain/02-patch-part-columns.sql`: with `patch_parts_version = 'v1'`, 26.8.36.3 and 26.10.3.7 write
   91,118 bytes, the same as 25.8 and 26.3. On those two builds the setting does not exist (Code 115). The
   `lightweight_update` `DELETE` patch is bigger for the same reason: 3,280 compressed bytes on 26.3, and on
   26.10 with `v1`, against 90,410 on 26.10 with `v2`. How much a `v2` patch grows depends on the width of
   the sort key.
3. **26.10 compresses large parts with `ZSTD(3)`; the mutation is unchanged.** On 26.10.3.7 the 20M-row
   part that `OPTIMIZE ... FINAL` writes is already `ZSTD(3)` (`system.parts.default_compression_codec`,
   41.2 MB), where 25.8 to 26.8 write `LZ4` (162 MB). A mutation that rewrites only some columns keeps the
   source part's codec (`MutateTask.cpp`), so `v` is rewritten with `ZSTD(3)`. The cause is [ClickHouse#108786](https://github.com/ClickHouse/ClickHouse/pull/108786) ("Switch the
   default compression to ZSTD(3) for table data and network", backward incompatible, merged into
   26.9.1.810). For a column with no codec, no `default_compression_codec` table setting and no matching
   `<compression>` case, MergeTree now uses `LZ4` below 100 MiB and `ZSTD(3)` at or above
   (`min_part_size_for_default_codec` in `src/Storages/CompressionCodecSelector.h`). It judges a merge by
   the compressed size of its source parts and an insert by 0. The 2M-row part (16 MB) stays
   `LZ4`, so file 04 wrote 7 to 8 MB on every build. `explain/03-default-codec.sql`: the classic 1%
   mutation writes 20,478,234 bytes on 26.10.3.7 and 79,316,481 to 79,323,443 on 25.8 to 26.8. With
   `default_compression_codec = 'LZ4'`, 26.10.3.7 writes 79,323,441.

### Screens

Captured 2026-11-04 from ClickHouse's `/play` UI on local throwaway containers, for the notes article
`core-architecture/clickhouse-upsert`:

- [`images/01-patch-parts-26-10.png`](images/01-patch-parts-26-10.png) — `system.parts` of `pu_1p` on 26.10.3.7: the base part and one `patch-` part
- [`images/02-update-bytes-written-26-10.png`](images/02-update-bytes-written-26-10.png) — bytes written for the 1% change per mechanism, from `system.part_log`, 26.10.3.7
- [`images/03-collapsing-cancel-first-26-10.png`](images/03-collapsing-cancel-first-26-10.png) — after `OPTIMIZE … FINAL`: CollapsingMergeTree (cancel row first) vs VersionedCollapsingMergeTree, 26.10.3.7
- [`images/04-update-25-3-syntax-error.png`](images/04-update-25-3-syntax-error.png) — `UPDATE` on 25.3.14.14: Code 62

### Not verified here

- Distributed or replicated tables, `SharedMergeTree` and ClickHouse Cloud.
- Tables larger than 20M rows, concurrent writers, and changed rows clustered in a few granules.
- Wall-clock times: other containers were running (see RESULTS.md).

Verified on 24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3 and 26.10.3.7, 2026-11-04 (`./run_matrix.py`, all six; `tools/hol run` on 26.10.3.7).

---

## 한국어

ClickHouse에서 행을 바꾸는 모든 방법을 같은 SQL로 여섯 빌드(LTS 24.8, 25.3, 25.8, 26.3, 26.8과 최신
stable 26.10)에서 실행합니다. 방법마다 그 버전에서 실행되는지(안 되면 오류 코드), 걸리는 시간,
쓰는 양(`system.part_log`의 바이트), 변경이 보이기까지의 시간, 이후 `SELECT`에 드는 비용을 기록합니다.
changelog를 인용한 내용은 없고, [RESULTS.md](RESULTS.md)의 모든 셀은 실행 결과입니다. 원시 데이터
(`query_log` 행 포함)는 `results/<버전>.json`에 있습니다.

대상: `ReplacingMergeTree`(`is_deleted` 유무), `CollapsingMergeTree`, `VersionedCollapsingMergeTree`,
`CoalescingMergeTree`, 기존 `ALTER TABLE ... UPDATE`, SQL `UPDATE`(패치 파트), 더 높은 버전으로
재삽입, on-the-fly 뮤테이션, 세 종류의 `DELETE`.

### 실행

```bash
cd workload/upsert-across-versions
./run_matrix.py                      # 여섯 버전 전부, 약 17분. 이미지는 미리 받아 둬야 함
./run_matrix.py --versions 26.10     # 한 버전(versions.txt 줄의 접두사)
./run_matrix.py --only 04            # 파일 또는 probe id 접두사. 결과는 JSON에 병합
./run_matrix.py --report-only        # results/*.json으로 RESULTS.md 재생성
tools/hol run workload/upsert-across-versions   # 저장소 루트에서: 26.10에서만 실행, 예외가 없어야 함
```

`versions.txt`는 정확한 태그를 오래된 순으로 고정합니다. `run_matrix.py`는
[workload/join-across-versions](../join-across-versions/)와 같은 파일입니다(컨테이너 이름은 여기서
`uav-<태그>`, 거기서는 `jav-<태그>`). `-- probe: <id> [repeat=N] [value]`가 앞에 붙은 문장이 probe이고
나머지는 준비 문장입니다. `value`는 첫 결과 행을 표 셀에 넣습니다. `-- settings: a, b`는
`system.settings`, 없으면 `system.merge_tree_settings`(`[table]`로 표시)에서 찾습니다. 문장마다
`clickhouse-client`를 따로 호출하므로 단독 `SET`은 쓰지 않습니다.

### Probe

| 파일 | 내용 |
|---|---|
| `01-replacing.sql` | `ReplacingMergeTree(ver)`, `(ver, is_deleted)`. 키 200만 개, 1%를 더 높은 `ver`로 다시 쓰고 0.1%를 삭제 표시: `FINAL` 유무의 `count()`, `FINAL` 대 `argMax ... GROUP BY`(5회 반복), `OPTIMIZE ... FINAL`, `FINAL CLEANUP` |
| `02-collapsing.sql` | 취소 행을 상태 행보다 먼저 넣은 `CollapsingMergeTree`, `VersionedCollapsingMergeTree`. 상태 행 먼저 넣는 대조군 |
| `03-coalescing.sql` | 드문드문 채운 INSERT를 `CoalescingMergeTree`와 `ReplacingMergeTree`에 넣어 비교 |
| `04-update-mechanisms.sql` | 기존 `ALTER UPDATE`, `ReplacingMergeTree` 재삽입, 패치 파트 `UPDATE`를 각각 200만 행의 1행, 1%, 10%에 적용(테이블 하나씩): 소요 시간, 쓴 바이트, 패치 파트, 그리고 건드리지 않은 대조 테이블과 전체 스캔 `SELECT sum(v)`(5회) 비교 |
| `05-on-the-fly.sql` | 대기 중인 뮤테이션(`SYSTEM STOP MERGES`, `mutations_sync = 0`)을 `apply_mutations_on_fly` 1과 0으로 읽기 |
| `06-patch-accumulation.sql` | 한 행짜리 `UPDATE` 50번 연속: 1, 10, 50번째 뒤의 패치 파트 수, 스캔, 포인트 읽기. 이어서 `OPTIMIZE ... FINAL`과 `ALTER TABLE ... APPLY PATCHES` |
| `07-delete.sql` | `ALTER ... DELETE`, `DELETE FROM`, `lightweight_delete_mode = 'lightweight_update'`의 `DELETE FROM`: 시간, 바이트, `apply_deleted_mask` 1과 0의 `count()` |
| `08-scale.sql` | 04의 읽기 비용을 2,000만 행에서 측정(스캔 130~480 ms): 기존 `ALTER UPDATE`, 패치 파트 `UPDATE`, 재삽입을 1%와 10%에 적용하고 전체 스캔 집계와 10만 행 범위 읽기를 각 5회, 건드리지 않은 대조군과 비교 |
| `errors/01-expected-failures.sql` | 26.10에서도 실패하는 문장(블록 컬럼 없는 UPDATE, 강제 lightweight DELETE, 테이블 설정 없는 `CLEANUP`, 정렬 키 컬럼 UPDATE). `tools/hol`은 이 디렉터리를 실행하지 않고 러너는 실행합니다 |

최상위 파일의 모든 probe는 26.10에서 성공합니다(`tools/hol run`은 첫 예외에서 멈춥니다). 이전 버전의
실패는 결과이며 `✗ Code N`으로 표시됩니다(56 UNKNOWN_STORAGE, 62 SYNTAX_ERROR, 115 UNKNOWN_SETTING,
344 SUPPORT_IS_DISABLED, 420 CANNOT_UPDATE_COLUMN, 48 NOT_IMPLEMENTED).

### 버전별 변화

[RESULTS.md](RESULTS.md)에서만 가져온 내용입니다(2026-11-04 실행, CPU 12개, Docker VM 15.6 GiB). 실행
내내 다른 컨테이너가 돌고 있었고(버전별 CPU%는 RESULTS.md에 있고 26.10 실행은 약 300%의 다른 부하와
겹쳤습니다), 시간을 잰 대부분의 probe가 4~30 ms라서 몇 ms 차이는 아래에서 근거로 쓰지 않습니다.

- **패치 파트 `UPDATE`.** 24.8.14.39와 25.3.14.14에서는 문법 오류(Code 62), 25.8.33.6부터 실행됩니다.
  `enable_block_number_column = 1`, `enable_block_offset_column = 1`로 만든 테이블이 필요합니다(없으면
  Code 48, 25.8~26.10 동일, `err-update-no-block-columns`). 세션 설정은 필요 없습니다: `SETTINGS`
  절 없는 `04-pu-no-setting`이 25.8~26.10에서 실행됩니다. `allow_experimental_lightweight_update`는
  25.8부터 있고 `Beta`, 26.10에서는 `Production`입니다. 정렬 키 컬럼의 `UPDATE`는 패치 파트와 기존
  뮤테이션 모두 Code 420으로 실패합니다.
- **패치 파트의 모습.** `system.parts`에서 이름이 `patch-`로 시작하고(예: `patch-<해시>-all_4_4_0_3`)
  `part_type`은 Compact입니다. `system.part_log`에서는 `NewPart`입니다. `system.parts`에 패치 전용
  컬럼은 없어서 probe는 `startsWith(name, 'patch-')`로 찾습니다.
- **Lightweight `DELETE`.** `DELETE FROM`은 여섯 버전 모두에서 실행됩니다. `lightweight_delete_mode`는
  25.8부터 있고(기본 `alter_update`, 24.8과 25.3에서 지정하면 Code 115) 기본 모드의 `DELETE FROM`은
  200만 행의 1%에 대해 약 11 KB(24.8)~18 KB(26.10)를 쓰는 `MutatePart`이고, `ALTER ... DELETE`는
  16 MB를 씁니다. 블록 컬럼이 있는 테이블에서 `lightweight_delete_mode = 'lightweight_update'`를
  쓰면 패치 파트를 씁니다(`07-delete-patch-bytes`: 25.8과 26.3에서 5 KB, 26.8과 26.10에서 92 KB, `MutatePart`
  없음. 늘어난 이유는 패치 바이트와 같으며 아래 *실행 뒤 밝힌 원인*의 2번입니다). 블록 컬럼 없는 테이블에서 `lightweight_update_force`는 Code 344로 실패합니다
  (`err-delete-force-no-block-columns`). `apply_deleted_mask = 0`이면 삭제한 행이 다시 보입니다
  (`count()` 2,000,000 대 1,980,000). 모든 버전에서 같고 패치 모드는 25.8부터입니다.
- **패치 바이트.** 같은 1% 업데이트에서 패치 파트는 25.8.33.6과 26.3.62.3에서 93 KB(10%는 845 KB), 26.8.36.3과 26.10.3.7은 180 KB와 1.65 MB입니다.
  26.8부터 패치 파트가 테이블의 정렬 키도 저장하기 때문입니다(아래 2번).
- **On-the-fly 뮤테이션.** `apply_mutations_on_fly = 1`은 25.3.14.14부터 새 값을 반환하고, 24.8.14.39는
  설정은 있지만 읽으면 이전 값이 나옵니다(`05-read-on-fly`).
- **`APPLY PATCHES`.** `ALTER TABLE ... APPLY PATCHES`는 25.8~26.10에서 실행됐습니다. 패치 50개 뒤
  `OPTIMIZE ... FINAL`은 기본 파트 이름을 바꾸고(`all_1_2_1`에서 `all_1_2_2_101`) 50행을 담은 활성
  패치 파트 하나를 남겼고, `APPLY PATCHES`는 다시 이름을 바꿨습니다(`..._103`). 바로 뒤의 probe는
  25.8.33.6에서 활성 패치 파트를 찾지 못했고 26.3.62.3, 26.8.36.3, 26.10.3.7에서는 50행짜리 패치 파트가
  아직 활성이었습니다. 모든 빌드에서 이 파트는 백그라운드에서 지워지며, 25.8은 약 1초 뒤, 26.3~26.10은
  28~36초 뒤입니다(아래 1번). 스캔과 포인트 읽기 결과는 모든 단계에서 같습니다.
- **`ReplacingMergeTree`.** 여섯 버전 모두 같습니다: `FINAL` 없으면 2,020,000행, 있으면 2,000,000행.
  `is_deleted` 테이블의 일반 `OPTIMIZE FINAL`은 삭제 행 2,000개를 남기고(물리 2,000,000행),
  `OPTIMIZE ... FINAL CLEANUP`이 지웁니다(1,998,000). 단 테이블을
  `allow_experimental_replacing_merge_with_cleanup = 1`로 만들었을 때만이고, 아니면 모든 버전에서
  Code 344입니다.
- **취소 행이 먼저인 `CollapsingMergeTree`.** 여섯 버전 모두 같습니다. `OPTIMIZE ... FINAL` 뒤에도
  101,000행이 남습니다. 취소된 1,000개 키마다 -1 행과 +1 행이 둘 다 남습니다(`sum(sign)`은 99,000,
  -1 행은 1,000개). 머지 전 `FINAL`은 100,000행을 반환합니다. `HAVING sum(sign) > 0`은 올바른 99,000개
  키를 반환합니다. 상태 행을 먼저 넣은 대조군과, 취소 행이 먼저인 `VersionedCollapsingMergeTree`는
  모두 99,000행으로 끝납니다.
- **`CoalescingMergeTree`.** 24.8.14.39와 25.3.14.14에서는 Code 56(알 수 없는 엔진), 25.8.33.6부터
  드문드문 넣은 세 INSERT가 `FINAL`과 `OPTIMIZE` 뒤에 세 컬럼이 모두 채워진 키당 한 행이 됩니다.
  `ReplacingMergeTree`는 마지막 INSERT의 컬럼만 남깁니다.

### 200만 행의 1행 / 1% / 10%

쓴 바이트는 `system.part_log`(`ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']`)에서, 업데이트
시간은 단일 실행, `SELECT sum(v)`는 5회 반복의 중앙값(최솟값) ms입니다. 대조군: 건드리지 않은
`MergeTree`는 26.10에서 4 (4) ms, 24.8에서 9 (5), 건드리지 않은 `ReplacingMergeTree`의 `FINAL`은 26.10에서
5 (4). 값은 26.10.3.7이고 대괄호는 그 방법이 실행되는 가장 오래된 빌드(기존 방식과 재삽입은
24.8.14.39, 패치 파트는 25.8.33.6)입니다.

| 방법 | 비율 | 쓴 바이트 | 업데이트 시간 | `SELECT sum(v)` |
|---|---|---|---|---|
| 기존 `ALTER UPDATE` | 1행 | 8.0 MB [8.0 MB] | 90 ms [101] | 5 (4) [6 (5)] |
| | 1% | 7.9 MB [7.9 MB] | 98 ms [69] | 6 (5) [6 (5)] |
| | 10% | 7.2 MB [7.2 MB] | 75 ms [78] | 6 (4) [5 (5)] |
| 재삽입, `ReplacingMergeTree` | 1행 | 1.8 KB [0.9 KB] | 64 ms [2] | `FINAL` 6 (5) [18 (17)] |
| | 1% | 186 KB [179 KB] | 65 ms [11] | `FINAL` 14 (13) [23 (18)] |
| | 10% | 1.65 MB [1.64 MB] | 26 ms [85] | `FINAL` 16 (15) [34 (16)] |
| 패치 파트 `UPDATE` | 1행 | 2.0 KB [2.2 KB] | 4 ms [6] | 14 (10) [7 (6)] |
| | 1% | 180 KB [93 KB] | 21 ms [20] | 12 (11) [8 (7)] |
| | 10% | 1.65 MB [845 KB] | 28 ms [44] | 17 (11) [12 (10)] |

표를 읽는 법: 기존 뮤테이션은 모든 비율에서 `v` 컬럼 전체(약 8 MB)를 다시 쓰고, 재삽입과 패치
파트는 바뀐 행 수에 대략 비례해 씁니다. 변경 뒤 뮤테이션한 테이블의 스캔은 1 ms 해상도 안에서
대조군과 같습니다. 재삽입은 `FINAL`이 필요해서 26.10에서 14~16 ms(건드리지 않은
`ReplacingMergeTree`의 `FINAL`은 5 ms)이고, `FINAL` 없이 읽으면 빠르지만 틀립니다(다시 쓴 키가 두 번
합산됨). 패치가 별도 파트로 남아 있는 동안 패치 파트 테이블은 대조군 4 ms에 비해 12~17 ms입니다.
재삽입의 업데이트 시간은 26.10과 24.8 사이에 일의 차이보다 크게 달라서 잡음이므로 방법의 순위를
매기는 데 쓰지 마세요. 측정한 것은 200만 행 테이블 하나와 하나의 데이터 배치(1%, 10%에서 바뀐 행이
모든 granule에 퍼짐)뿐이고, 이 실습의 출발점이던 "10% 미만" 기준은 이 세 비율 밖에서는 검증하지
않았습니다.

### 2,000만 행에서의 읽기 비용(`08-scale.sql`)

같은 세 방법을 10배 크기에서 측정해 스캔이 130~480 ms가 되므로 1 ms 해상도가 더는 문제가 되지
않습니다. 테이블마다 변경 전에는 파트 하나이고, 패치 파트와 재삽입 테이블은 머지를 멈췄으며, 재삽입
테이블은 `FINAL`로 읽습니다. 스캔은 전체 행에 대한 `SELECT sum(sipHash64(v, s)), uniq(v)`, 범위 읽기는
정렬 키 기준 10만 id에 대한 같은 집계입니다. 셀은 5회 반복의 중앙값(최솟값) ms이며 26.10.3.7이 먼저이고
대괄호는 그 방법이 실행되는 가장 오래된 빌드(24.8.14.39, 패치 파트는 25.8.33.6)입니다. 버전당 74~121초가
걸렸고 다른 컨테이너가 돌고 있었으므로(CPU% 합계는 RESULTS.md, 1200% 중 88~459%) 약 30%보다 작은
차이는 잡음으로 보세요. 26.10.3.7에서는 `OPTIMIZE ... FINAL`이 2,000만 행 테이블을 모두 `ZSTD(3)`로,
다른 빌드는 `LZ4`로 씁니다(아래 3번). 패치 파트와 재삽입한 파트는 모든 빌드에서 `LZ4`입니다. 그래서
대괄호 값은 26.10 값과 빌드뿐 아니라 코덱도 다릅니다.

| 읽기 | 비율 | 건드리지 않은 대조군 | 기존 `ALTER UPDATE` | 패치 파트 `UPDATE` | 재삽입, `FINAL` |
|---|---|---|---|---|---|
| 전체 스캔 | 1% | 148 (134) [193 (172)] | 149 (124) [218 (189)] | 202 (185) [186 (173)] | 274 (248) [278 (224)] |
| 전체 스캔 | 10% | 148 (134) [193 (172)] | 161 (128) [159 (150)] | 242 (204) [270 (229)] | 255 (223) [376 (290)] |
| 범위, 10만 행 | 1% | 5 (3) [5 (5)] | 3 (3) [12 (7)] | 5 (4) [6 (5)] | 7 (5) [10 (8)] |
| 범위, 10만 행 | 10% | 5 (3) [5 (5)] | 4 (3) [14 (11)] | 5 (5) [8 (7)] | 6 (5) [17 (12)] |

재삽입 열의 대조군은 건드리지 않은 `ReplacingMergeTree`를 `FINAL`로 읽은 값으로, 전체 스캔은
26.10.3.7에서 154 (131), 24.8.14.39에서 170 (149), 범위는 3 (3)과 8 (4)입니다. 다른 열의 대조군은
건드리지 않은 `MergeTree`입니다. `FINAL` 없이 읽으면 재삽입 테이블은 26.10에서 157 (148) ms이지만
합계가 틀립니다.

26.10 숫자가 보여 주는 것: 기존 뮤테이션을 한 테이블은 대조군과 같은 속도로 스캔되고, 패치 파트
테이블은 대조군의 약 1.4~1.6배, `FINAL` 테이블은 약 1.7~1.8배입니다(건드리지 않은 `FINAL` 테이블
154 (131) 기준으로는 약 1.7배). 정렬 키 범위 읽기는 모든 방법에서 한 자릿수 ms입니다. 업데이트
자체(단일 실행, 26.10.3.7): 기존 방식은 1%에 1.37초, 10%에 0.80초로 둘 다 20 MB를 쓰고, 패치 파트는
125 ms와 269 ms에 1.8 MB와 16 MB, 재삽입은 63 ms와 255 ms에 1.8 MB와 9.2 MB를 씁니다.

같은 파일에서 본 빌드 간 변화:

- **패치 파트 쓴 바이트.** 같은 바뀐 행(20만, 200만)에 대해 25.8.33.6과 26.3.62.3은 916 KB(1%)와
  8.4 MB(10%), 26.8.36.3과 26.10.3.7은 1.79 MB와 16.4 MB입니다(아래 2번).
- **패치 파트 업데이트 시간(1% / 10%).** 25.8 137 / 734 ms, 26.3 141 / 553 ms, 26.8 100 / 832 ms,
  26.10 125 / 269 ms(단일 실행).
- **패치 파트 스캔(1% / 10%).** 25.8 186 (173) / 270 (229), 대조군 252 (203). 26.3 367 (226) / 229 (160),
  대조군 147 (120). 26.8 281 (200) / 242 (213), 대조군 209 (166). 26.10 202 (185) / 242 (204), 대조군
  148 (134). 부하가 있는 이 머신에서 대조군 자체가 빌드 사이에 1.7배 달라지므로 25.8~26.8의 오버헤드
  비율은 신뢰할 수 없고, 이 실행으로는 빌드를 구분할 수 없습니다.
- **기존 뮤테이션 쓴 바이트.** 24.8~26.8은 79 MB(1%), 72 MB(10%), 26.10.3.7은 20.5 MB, 19.6 MB입니다.
  200만 행(파일 04)에서는 여섯 빌드 모두 7~8 MB였습니다. 뮤테이션은 같고, 26.10이 2,000만 행 파트를
  `ZSTD(3)`로 압축합니다(아래 3번).
- **불가.** 패치 파트는 파일 04처럼 24.8과 25.3에서 Code 62이고, 그 빌드의 기존 방식과 재삽입
  테이블은 실행됐습니다.

### 실행 뒤 밝힌 원인(2026-11-05)

위 차이 가운데 셋은 처음에 원인 없이 기록했습니다. 2026-11-05에 25.8.33.6, 26.3.62.3, 26.8.36.3,
26.10.3.7 일회용 컨테이너에서 대조군과 함께 하나씩 재현했습니다(다른 컨테이너의 CPU는 시작 때 1200% 중
약 230%, 끝날 때 43%였고, 시간은 쓰지 않고 바이트, 파트 이름, 로그 줄만 씁니다). 원인은 ClickHouse
소스에서 읽었습니다. 25.8은 `v25.8.33.6-lts`이고, 26.3.62.3, 26.8.36.3, 26.10.3.7의 빌드 커밋
(`system.build_options`)은 GitHub에 없어서 가장 가까운 공개 태그 `v26.3.60.2-lts`, `v26.8.34.13-lts`,
`v26.10.2.103-stable`을 읽었습니다. 셋 다 버그가 아닙니다. 재현 SQL은 [`explain/`](explain/)에 있고
`clickhouse-client --multiquery < explain/<파일>`로 실행합니다(러너와 `tools/hol`은 이 디렉터리를
실행하지 않습니다).

1. **`APPLY PATCHES` 뒤에 남은 패치 파트는 정리 작업이 나중에 지웁니다.** 모든 빌드의 서버 로그에
   그 파트에 대한 `Will drop unused patch part ...`가 있습니다. `APPLY PATCHES`가 끝나고 25.8.33.6은
   1.0초, 26.3.62.3은 28.6초, 26.8.36.3은 27.9초, 26.10.3.7은 36.3초 뒤입니다. 25.8에서는
   `clearUnusedPatchParts`가 테이블의 머지·뮤테이션 스케줄러(`StorageMergeTree::scheduleDataProcessingJob`)에서
   `merge_tree_clear_old_parts_interval_seconds`(1초)마다 최대 한 번 돌았습니다. 26.3부터는 별도 정리
   스레드에서 돕니다([ClickHouse#91574](https://github.com/ClickHouse/ClickHouse/pull/91574), 26.3.1.471에
   머지, `MergeTreeCleanupThread`). 이 스레드는 `cleanup_delay_period`(30초)에서
   `max_cleanup_delay_period`(300초) 사이를 쉬고(직전에 지운 것이 적을수록 길게), 여기에
   `cleanup_delay_period_random_add`(10초)까지 더합니다. 설정 설명도 `remove_unused_patch_parts`가
   "in background"로 지운다고 적고 있습니다. `explain/01-patch-cleanup.sql`은 `APPLY PATCHES` 3초 뒤에
   `system.parts`를 읽습니다. 기본 설정이면 패치 파트가 25.8에서는 없고 26.3~26.10에서는 아직 있습니다.
   정리 설정 세 개를 1, 1, 0으로 두면 네 빌드 모두 없고, 같은 주기에 `remove_unused_patch_parts = 0`이면
   네 빌드 모두 남습니다. `cleanup_delay_period = 1`만으로는 부족합니다. 거의 지운 것이 없던 직전 정리
   뒤에 26.10의 trace는 `Scheduling next cleanup after 75000ms`였습니다.
2. **26.8부터 패치 파트가 테이블의 정렬 키를 저장합니다.** 26.8에 테이블 설정 `patch_parts_version`이
   생겼고 기본값은 `v2`입니다([ClickHouse#103182](https://github.com/ClickHouse/ClickHouse/pull/103182)
   "Lightweight Updates v2", 하위 호환이 깨지는 변경, [ClickHouse#116007](https://github.com/ClickHouse/ClickHouse/pull/116007)로 다시 들어가
   [ClickHouse#116373](https://github.com/ClickHouse/ClickHouse/pull/116373)으로 26.8에 백포트,
   `v26.8.1.2041-lts`부터 기본값 `v2`). `v1` 패치 파트는 `v`, `_part`, `_part_offset`,
   `_part_data_version`, `_block_number`, `_block_offset`을 담고 `(_part, _part_offset)`로 정렬됩니다.
   `v2` 패치 파트는 `_part_offset` 대신 정렬 키 컬럼(여기서는 `id`)을 담고
   `(id, _block_number, _block_offset)`로 정렬됩니다. 설정 설명에 따르면 `v2` 패치를 적용할 때 메모리는
   패치 전체가 아니라 같은 키가 이어지는 가장 긴 구간만큼 필요합니다. 200만 행의 1%에서 비압축 크기는 둘 다
   820,086바이트입니다. 차이는 코덱입니다. `_part_offset`은 `_block_offset`의 `Delta, LZ4` 코덱을 받고
   (`PatchParts/PatchPartsUtils.cpp`의 `addCodecsForPatchSystemColumns`, `clickhouse-compressor --stat`으로
   압축 블록당 약 300바이트), `id`는 테이블 코덱인 `LZ4`를 받습니다(블록당 36~52 KB, `v`와 같은 양).
   그래서 압축 크기가 91,118 대 178,248바이트입니다. `explain/02-patch-part-columns.sql`:
   `patch_parts_version = 'v1'`이면 26.8.36.3과 26.10.3.7도 91,118바이트로 25.8, 26.3과 같습니다. 25.8과
   26.3에는 이 설정이 없습니다(Code 115). `lightweight_update` `DELETE` 패치가 커진 이유도 같습니다. 26.3과
   `v1`의 26.10에서 압축 3,280바이트, `v2`의 26.10에서 90,410바이트입니다. `v2` 패치가 얼마나 커지는지는
   정렬 키의 폭에 달려 있습니다.
3. **26.10은 큰 파트를 `ZSTD(3)`로 압축합니다. 뮤테이션은 그대로입니다.** 26.10.3.7에서는
   `OPTIMIZE ... FINAL`이 쓴 2,000만 행 파트가 이미 `ZSTD(3)`입니다(`system.parts.default_compression_codec`,
   41.2 MB). 25.8~26.8은 `LZ4`(162 MB)입니다. 일부 컬럼만 다시 쓰는 뮤테이션은 원본 파트의 코덱을
   유지하므로(`MutateTask.cpp`) `v`도 `ZSTD(3)`로 다시 쓰입니다. 원인은
   [ClickHouse#108786](https://github.com/ClickHouse/ClickHouse/pull/108786)("Switch the default compression
   to ZSTD(3) for table data and network", 하위 호환이 깨지는 변경, 26.9.1.810에 머지)입니다. 코덱이 없는
   컬럼에 `default_compression_codec` 테이블 설정도, 맞는 `<compression>` case도 없으면 MergeTree는 이제
   100 MiB 미만은 `LZ4`, 이상은 `ZSTD(3)`을 씁니다(`src/Storages/CompressionCodecSelector.h`의
   `min_part_size_for_default_codec`). 머지는 원본 파트들의 압축 크기로, INSERT는 0으로 판단합니다.
   200만 행 파트(16 MB)는 `LZ4`로 남아서 파일 04는 모든 빌드에서 7~8 MB를 썼습니다.
   `explain/03-default-codec.sql`: 기존 방식 1% 뮤테이션은 26.10.3.7에서 20,478,234바이트, 25.8~26.8에서
   79,316,481~79,323,443바이트를 씁니다. `default_compression_codec = 'LZ4'`이면 26.10.3.7도
   79,323,441바이트입니다.

### 화면

2026-11-04, 로컬 일회용 컨테이너의 ClickHouse `/play` 화면에서 노트 글 `core-architecture/clickhouse-upsert`용으로 찍었습니다.

- [`images/01-patch-parts-26-10.png`](images/01-patch-parts-26-10.png) — 26.10.3.7의 `pu_1p` `system.parts`: 원본 파트와 `patch-` 파트 하나
- [`images/02-update-bytes-written-26-10.png`](images/02-update-bytes-written-26-10.png) — 1% 수정의 방식별 쓴 바이트(`system.part_log`, 26.10.3.7)
- [`images/03-collapsing-cancel-first-26-10.png`](images/03-collapsing-cancel-first-26-10.png) — `OPTIMIZE … FINAL` 뒤 CollapsingMergeTree(취소 행 먼저)와 VersionedCollapsingMergeTree, 26.10.3.7
- [`images/04-update-25-3-syntax-error.png`](images/04-update-25-3-syntax-error.png) — 25.3.14.14의 `UPDATE`: Code 62

### 검증하지 않은 것

- 분산·복제 테이블, `SharedMergeTree`, ClickHouse Cloud.
- 2,000만 행보다 큰 테이블, 동시 쓰기, 바뀐 행이 몇 개 granule에 몰린 경우.
- 절대 시간: 다른 컨테이너가 돌고 있었습니다(RESULTS.md 참조).

24.8.14.39, 25.3.14.14, 25.8.33.6, 26.3.62.3, 26.8.36.3, 26.10.3.7에서 검증, 2026-11-04(`./run_matrix.py`로 여섯 빌드 모두, `tools/hol run`은 26.10.3.7).
