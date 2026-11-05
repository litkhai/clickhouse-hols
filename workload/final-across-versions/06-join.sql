-- settings: final, analyzer_compatibility_apply_final_to_all_joined_tables
-- FINAL and JOIN. dim holds 1,000 keys twice (ver 1 and ver 2, merges stopped); fact has 100,000 rows, k = number % 1000
-- (100 rows per key).

CREATE DATABASE IF NOT EXISTS final_lab;

DROP TABLE IF EXISTS final_lab.dim;

DROP TABLE IF EXISTS final_lab.fact;

CREATE TABLE final_lab.dim
(
    k    UInt64,
    name String,
    ver  UInt32
)
ENGINE = ReplacingMergeTree(ver)
ORDER BY k;

SYSTEM STOP MERGES final_lab.dim;

INSERT INTO final_lab.dim SELECT number, concat('v1-', toString(number)), 1 FROM numbers(1000);

INSERT INTO final_lab.dim SELECT number, concat('v2-', toString(number)), 2 FROM numbers(1000);

CREATE TABLE final_lab.fact
(
    k UInt64
)
ENGINE = MergeTree
ORDER BY k;

INSERT INTO final_lab.fact SELECT number % 1000 FROM numbers(100000);

-- probe: 06-join-plain value
-- Correct: 200000 (no FINAL: every fact row meets both versions of its key).
SELECT count() FROM final_lab.fact AS f JOIN final_lab.dim AS d ON f.k = d.k;

-- probe: 06-join-final-alias-last value
-- Correct: 100000 (FINAL on the right table, written after the alias; the other order, `dim FINAL AS d`, is in errors/).
SELECT count() FROM final_lab.fact AS f JOIN final_lab.dim AS d FINAL ON f.k = d.k;

-- probe: 06-join-setting value
-- Correct: 100000.
SELECT count() FROM final_lab.fact AS f JOIN final_lab.dim AS d ON f.k = d.k SETTINGS final = 1;

-- probe: 06-self-left-final value
-- Correct: 2000 (SQL-correct: 1000 deduplicated left rows x 2 physical right rows; FINAL only on the left table).
SELECT count() FROM final_lab.dim AS d1 FINAL JOIN final_lab.dim AS d2 ON d1.k = d2.k;

-- probe: 06-self-left-final-compat value
-- Correct: 2000 under the SQL reading (FINAL only on the left); 1000 if the setting applies FINAL to every joined table.
SELECT count() FROM final_lab.dim AS d1 FINAL JOIN final_lab.dim AS d2 ON d1.k = d2.k SETTINGS analyzer_compatibility_apply_final_to_all_joined_tables = 1;
