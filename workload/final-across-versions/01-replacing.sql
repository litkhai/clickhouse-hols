-- settings: final, enable_vertical_final, max_final_threads, do_not_merge_across_partitions_select_final, enable_automatic_decision_for_merging_across_partitions_for_final, optimize_move_to_prewhere, optimize_move_to_prewhere_if_final, use_skip_indexes_if_final, use_skip_indexes_if_final_exact_mode, use_skip_indexes_in_final_exact_mode, apply_row_policy_after_final, apply_prewhere_after_final, defer_partition_pruning_after_final, split_parts_ranges_into_intersecting_and_non_intersecting_final, split_intersecting_parts_ranges_into_layers_final, query_plan_optimize_lazy_final, analyzer_compatibility_apply_final_to_all_joined_tables
-- SELECT ... FINAL on ReplacingMergeTree: does every spelling of "give me the newest row per key" return the same answer?
-- 1M keys (ver = 1), then 10,000 keys (id = number * 100) re-written with ver = 2 and v = id + 1.
-- rmt_del also marks every tenth re-written key is_deleted = 1 (1,000 deleted keys).
-- Merges are stopped so that "before the merge" is deterministic.

CREATE DATABASE IF NOT EXISTS final_lab;

DROP VIEW IF EXISTS final_lab.rmt_latest;

DROP VIEW IF EXISTS final_lab.rmt_view;

DROP TABLE IF EXISTS final_lab.rmt;

DROP TABLE IF EXISTS final_lab.rmt_del;

CREATE TABLE final_lab.rmt
(
    id  UInt64,
    v   UInt64,
    ver UInt32
)
ENGINE = ReplacingMergeTree(ver)
ORDER BY id;

SYSTEM STOP MERGES final_lab.rmt;

INSERT INTO final_lab.rmt SELECT number, number, 1 FROM numbers(1000000);

INSERT INTO final_lab.rmt SELECT number * 100, number * 100 + 1, 2 FROM numbers(10000);

CREATE TABLE final_lab.rmt_del
(
    id         UInt64,
    v          UInt64,
    ver        UInt32,
    is_deleted UInt8
)
ENGINE = ReplacingMergeTree(ver, is_deleted)
ORDER BY id;

SYSTEM STOP MERGES final_lab.rmt_del;

INSERT INTO final_lab.rmt_del SELECT number, number, 1, 0 FROM numbers(1000000);

INSERT INTO final_lab.rmt_del SELECT number * 100, number * 100 + 1, 2, number % 10 = 0 FROM numbers(10000);

CREATE VIEW final_lab.rmt_latest AS SELECT * FROM final_lab.rmt FINAL;

CREATE VIEW final_lab.rmt_view AS SELECT * FROM final_lab.rmt;

-- probe: 01-count-plain value
-- Correct (physical rows): 1010000.
SELECT count() FROM final_lab.rmt;

-- probe: 01-count-final value
-- Correct: 1000000.
SELECT count() FROM final_lab.rmt FINAL;

-- probe: 01-count-setting value
-- Correct: 1000000.
SELECT count() FROM final_lab.rmt SETTINGS final = 1;

-- probe: 01-count-subquery-setting value
-- Correct: 1000000.
SELECT count() FROM (SELECT id FROM final_lab.rmt) SETTINGS final = 1;

-- probe: 01-count-view value
-- Correct: 1000000.
SELECT count() FROM final_lab.rmt_latest;

-- probe: 01-count-view-final value
-- Correct: 1000000 if FINAL reaches the table under the view (physical rows: 1010000); the view has no FINAL of its own.
SELECT count() FROM final_lab.rmt_view FINAL;

-- probe: 01-point-final value
-- Correct: 501 2 (key 500 = 5 * 100 was re-written with v = 501, ver = 2).
SELECT v, ver FROM final_lab.rmt FINAL WHERE id = 500;

-- probe: 01-sum-final value
-- Correct: 499999510000 (sum 0..999999 = 499999500000, plus 1 for each of the 10000 re-written keys).
SELECT sum(v) FROM final_lab.rmt FINAL;

-- probe: 01-sum-argmax value
-- Correct: 499999510000.
SELECT sum(v) FROM (SELECT id, argMax(v, ver) AS v FROM final_lab.rmt GROUP BY id);

-- probe: 01-sum-limitby value
-- Correct: 499999510000.
SELECT sum(v) FROM (SELECT id, v FROM final_lab.rmt ORDER BY id, ver DESC LIMIT 1 BY id);

-- probe: 01-sum-final-novertical value
-- Correct: 499999510000.
SELECT sum(v) FROM final_lab.rmt FINAL SETTINGS enable_vertical_final = 0;

-- probe: 01-del-count-plain value
-- Correct (physical rows): 1010000.
SELECT count() FROM final_lab.rmt_del;

-- probe: 01-del-count-final value
-- Correct: 999000 (1000000 keys minus 1000 deleted).
SELECT count() FROM final_lab.rmt_del FINAL;

-- probe: 01-del-count-setting value
-- Correct: 999000.
SELECT count() FROM final_lab.rmt_del SETTINGS final = 1;

SYSTEM START MERGES final_lab.rmt;

-- probe: 01-optimize-final
OPTIMIZE TABLE final_lab.rmt FINAL;

-- probe: 01-count-plain-after value
-- Correct: 1000000 (one part left, one row per key).
SELECT count() FROM final_lab.rmt;

-- probe: 01-settings-changes show
-- FINAL-related rows of system.settings_changes, oldest version first.
SELECT version, tupleElement(c, 1) AS setting, tupleElement(c, 2) AS previous, tupleElement(c, 3) AS new_value FROM system.settings_changes ARRAY JOIN changes AS c WHERE tupleElement(c, 1) ILIKE '%final%' ORDER BY arrayMap(x -> toUInt32OrZero(x), splitByChar('.', version)), setting;
