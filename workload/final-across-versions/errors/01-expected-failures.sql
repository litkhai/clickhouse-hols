-- Probes whose error may be the result: they are not run by tools/hol (top-level files only).
-- The runner records the error code per version; any that succeed on 26.10 are noted in the lab README, not hidden here.

CREATE DATABASE IF NOT EXISTS final_lab;

DROP TABLE IF EXISTS final_lab.err_plain;

DROP TABLE IF EXISTS final_lab.err_mem;

DROP TABLE IF EXISTS final_lab.err_rmt;

DROP TABLE IF EXISTS final_lab.err_dim;

DROP TABLE IF EXISTS final_lab.err_fact;

CREATE TABLE final_lab.err_plain (id UInt64, v UInt64) ENGINE = MergeTree ORDER BY id;

INSERT INTO final_lab.err_plain SELECT number, number FROM numbers(1000);

CREATE TABLE final_lab.err_mem (id UInt64, v UInt64) ENGINE = Memory;

INSERT INTO final_lab.err_mem SELECT number, number FROM numbers(1000);

CREATE TABLE final_lab.err_rmt (id UInt64, v UInt64, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

INSERT INTO final_lab.err_rmt SELECT number, number, 1 FROM numbers(1000);

CREATE TABLE final_lab.err_dim (k UInt64, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY k;

CREATE TABLE final_lab.err_fact (k UInt64) ENGINE = MergeTree ORDER BY k;

-- probe: err-final-plain-mergetree value
-- FINAL on a plain MergeTree.
SELECT count() FROM final_lab.err_plain FINAL;

-- probe: err-final-memory value
-- FINAL on a Memory table.
SELECT count() FROM final_lab.err_mem FINAL;

-- probe: err-final-sample value
-- FINAL SAMPLE on a ReplacingMergeTree that has no SAMPLE BY.
SELECT count() FROM final_lab.err_rmt FINAL SAMPLE 1/2;

-- probe: err-join-final-before-alias value
-- FINAL written before the alias in a JOIN (`dim FINAL AS d`).
SELECT count() FROM final_lab.err_fact AS f JOIN final_lab.err_dim FINAL AS d ON f.k = d.k;
